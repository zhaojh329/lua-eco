--[[
 * MIT License
 *
 * Copyright (c) 2022 Jianhui Zhao <zhaojh329@gmail.com>
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
--]]

local socket = require 'eco.core.socket'
local file = require 'eco.core.file'
local sys = require 'eco.core.sys'
local bufio = require 'eco.bufio'

local sendfile = file.sendfile
local write = file.write

local read = file.read
local read_to_buffer = file.read_to_buffer

local str_sub = string.sub
local concat = table.concat
local type = type

local SOCK_MT_STREAM = 0
local SOCK_MT_DGRAM  = 1
local SOCK_MT_SERVER = 2
local SOCK_MT_CLIENT = 3
local SOCK_MT_ESTAB  = 4

local M = {}

local function sock_getsockname(sock)
    local mt = getmetatable(sock)
    return socket.getsockname(mt.fd)
end

local function sock_getpeername(sock)
    local mt = getmetatable(sock)
    return socket.getpeername(mt.fd)
end

local function sock_getfd(sock)
    local mt = getmetatable(sock)
    return mt.fd
end

local function sock_setoption(sock, ...)
    local fd = sock_getfd(sock)
    return socket.setoption(fd, ...)
end

local function sock_getoption(sock, ...)
    local fd = sock_getfd(sock)
    return socket.getoption(fd, ...)
end

local function sock_close(sock)
    local mt = getmetatable(sock)

    if mt.fd < 0 then
        return
    end

    if mt.name ~= SOCK_MT_ESTAB then
        local addr = socket.getsockname(mt.fd)
        if addr and addr.family == socket.AF_UNIX then
            if addr.path and file.access(addr.path) then
                os.remove(addr.path)
            end
        end
    end

    file.close(mt.fd)
    mt.fd = -1
end

local function sock_closed(sock)
    return sock_getfd(sock) < 0
end

--[[
    syntax:
        data, err, partial = tcpsock:recv(size, timeout)
        data, err, partial = tcpsock:recv(pattern?, timeout)

    In case of success, it returns the data received; in case of error, it returns
    nil with a string describing the error and the partial data received so far.

    If a number-like argument is specified, then it is interpreted as a size. This
    method will return any data received at most size bytes or an error occurs.

    If a non-number-like string argument is specified, then it is interpreted as a
    "pattern". The following patterns are supported:
        '*a': reads from the socket until the connection is closed.
        '*l': reads a line of text from the socket. Not including the end-of-line bytes("\r\n" or "\n").

    If no argument is specified, then it is assumed to be the pattern '*l', that is, the line reading pattern.
--]]
local function sock_recv(sock, pattern, timeout)
    local mt = getmetatable(sock)
    local fd = mt.fd
    local b = mt.b

    if fd < 0 then
        return nil, 'closed'
    end

    if mt.name == SOCK_MT_DGRAM then
        if not mt.ior:wait(timeout) then
            return nil, 'timeout'
        end

        return socket.recv(fd, pattern)
    end

    if type(pattern) == 'number' then
        if pattern <= 0 then return '' end
        return b:read(pattern, timeout)
    end

    if pattern == '*a' then
        local data = {}
        local chunk, err
        while true do
            chunk, err = b:read(4096)
            if not chunk then break end
            data[#data + 1] = chunk
        end

        if #data == 0 then
            return nil, err
        end

        if err == 'closed' then
            return concat(data)
        end

        return nil, err, concat(data)
    end

    if not pattern or pattern == '*l' then
        return b:readline(timeout)
    end

    error('invalid pattern:' .. tostring(pattern))
end

--[[
    syntax: data, err, partial = tcpsock:recvfull(size, timeout)
    This method will not return until it reads exactly this size of data or an error occurs.
--]]
local function sock_recvfull(sock, size, timeout)
    local mt = getmetatable(sock)
    local fd = mt.fd
    local b = mt.b

    if fd < 0 then
        return nil, 'closed'
    end

    if size <= 0 then return '' end

    return b:readfull(size, timeout)
end

local function sock_discard(sock, size, timeout)
    local mt = getmetatable(sock)
    local fd = mt.fd
    local b = mt.b

    if fd < 0 then
        return nil, 'closed'
    end

    if size <= 0 then return 0 end

    return b:discard(size, timeout)
end

local function sock_send(sock, data)
    if sock:closed() then
        return nil, 'closed'
    end

    local mt = getmetatable(sock)
    local iow = mt.iow
    local fd = mt.fd
    local total = #data
    local sent = 0
    local ok, n, err

    while sent < total do
        ok, err = iow:wait()
        if not ok then
            return nil, err, sent
        end

        n, err = write(fd, str_sub(data, sent + 1))
        if not n then
            return nil, err, sent
        end
        sent = sent + n
    end

    return sent
end

local function sock_sendfile(sock, fd, count, offset)
    if sock:closed() then
        return nil, 'closed'
    end

    local mt = getmetatable(sock)
    local iow = mt.iow
    local sfd = mt.fd
    local sent = 0

    while count > 0 do
        local ok, err = iow:wait()
        if not ok then
            return nil, err, sent
        end

        local ret, offset_ret = sendfile(sfd, fd, offset, count)
        if not ret then
            return nil, offset_ret, sent
        end

        sent = sent + ret
        count = count - ret

        if offset_ret then
            offset = offset_ret
        end
    end
end

local function sock_recvfrom(sock, n, timeout)
    if sock:closed() then
        return nil, 'closed'
    end

    local mt = getmetatable(sock)

    if not mt.ior:wait(timeout) then
        return nil, 'timeout'
    end

    return socket.recvfrom(mt.fd, n)
end

local function sock_sendto(sock, data, ...)
    if sock:closed() then
        return nil, 'closed'
    end

    local mt = getmetatable(sock)
    local family = mt.family
    local arg = {...}

    if family == socket.AF_INET then
        local ip, port = arg[1], arg[2]
        return socket.sendto(mt.fd, data, ip, port)
    elseif family == socket.AF_INET6 then
        local ip, port = arg[1], arg[2]
        return socket.sendto6(mt.fd, data, ip, port)
    else
        local path = arg[1]
        return socket.sendto_unix(mt.fd, data, path)
    end
end

local client_methods = {
    close = sock_close,
    closed = sock_closed,
    getfd = sock_getfd,
    recv = sock_recv,
    recvfull = sock_recvfull,
    discard = sock_discard,
    send = sock_send,
    sendfile = sock_sendfile,
    getsockname = sock_getsockname,
    getpeername = sock_getpeername,
    setoption = sock_setoption,
    getoption = sock_getoption
}

local function sock_bind(sock, ...)
    local mt = getmetatable(sock)
    local family = mt.family
    local arg = {...}

    local ok, err

    if family == socket.AF_INET then
        local ip, port = arg[1], arg[2]
        ok, err = socket.bind(mt.fd, ip, port)
    elseif family == socket.AF_INET6 then
        local ip, port = arg[1], arg[2]
        ok, err = socket.bind6(mt.fd, ip, port)
    else
        local path = arg[1]
        ok, err = socket.bind_unix(mt.fd, path)
    end

    if not ok then
        return nil, sys.strerror(err)
    end

    return true
end

local function create_bufio(mt)
    local reader = {
        fd = mt.fd,
        ior = mt.ior
    }

    function reader:read(n, timeout)
        if not self.ior:wait(timeout) then
            return nil, 'timeout'
        end

        local data, err = read(self.fd, n, timeout)
        if not data then
            return nil, err
        end

        if #data == 0 then
            return nil, 'closed'
        end

        return data
    end

    function reader:read2b(b, timeout)
        if b:room() == 0 then
            return nil, 'buffer is full'
        end

        if not self.ior:wait(timeout) then
            return nil, 'timeout'
        end

        local r, err = read_to_buffer(self.fd, b, timeout)
        if not r then
            return nil, err
        end

        if r == 0 then
            return nil, 'closed'
        end

        return r, err
    end

    return bufio.new(reader)
end

local function sock_update_mt(sock, methods, name)
    local mt = getmetatable(sock)
    mt.name = name
    mt.__index = methods

    if name == SOCK_MT_SERVER then
        mt.iow = nil
    else
        mt.b = create_bufio(mt)
    end
end

local function sock_setmetatable(fd, family, typ, methods, name)
    local sock = {}

    if tonumber(_VERSION:match('%d%.%d')) < 5.2 then
        local __prox = newproxy(true)
        getmetatable(__prox).__gc = function() sock_close(sock) end
        sock[__prox] = true
    end

    local mt = {
        name = name,
        family = family,
        typ = typ,
        fd = fd,
        ior = eco.watcher(eco.IO, fd),
        iow = eco.watcher(eco.IO, fd, eco.WRITE),
        __index = methods,
        __gc = methods.close
    }

    if name == SOCK_MT_ESTAB then
        mt.b = create_bufio(mt)
    end

    setmetatable(sock, mt)

    return sock
end

local function sock_accept(sock, timeout)
    if sock:closed() then
        return nil, 'closed'
    end

    local mt = getmetatable(sock)

    if not mt.ior:wait(timeout) then
        return nil, 'timeout'
    end

    local fd, addr = socket.accept(mt.fd)
    if not fd then
        return nil, sys.strerror(addr)
    end

    return sock_setmetatable(fd, mt.family, mt.typ, client_methods, SOCK_MT_ESTAB), addr
end

local server_methods = {
    close = sock_close,
    closed = sock_closed,
    getfd = sock_getfd,
    accept = sock_accept,
    getsockname = sock_getsockname,
    setoption = sock_setoption,
    getoption = sock_getoption
}

local function sock_listen(sock, backlog)
    local fd = sock_getfd(sock)
    local ok, err = socket.listen(fd, backlog)
    if not ok then
        return false, sys.strerror(err)
    end

    sock_update_mt(sock, server_methods, SOCK_MT_SERVER)

    return true
end

local function sock_connect_ok(sock)
    local mt = getmetatable(sock)

    if mt.typ == socket.SOCK_STREAM then
        sock_update_mt(sock, client_methods, SOCK_MT_CLIENT)
    end

    return true
end

local function sock_connect(sock, ...)
    if sock:closed() then
        return false, 'closed'
    end

    local mt = getmetatable(sock)
    local family = mt.family
    local ok, err

    if family == socket.AF_INET then
        ok, err = socket.connect(mt.fd, ...)
    elseif family == socket.AF_INET6 then
        ok, err = socket.connect6(mt.fd, ...)
    else
        ok, err = socket.connect_unix(mt.fd, ...)
    end

    if not ok then
        if err == sys.EINPROGRESS then
            if not mt.iow:wait(3.0) then
                return nil, 'timeout'
            end

            err = socket.getoption(mt.fd, 'error')
            if err == 0 then
                return sock_connect_ok(sock)
            end
        end
        return false, sys.strerror(err)
    end

    return sock_connect_ok(sock)
end

local stream_methods = {
    close = sock_close,
    closed = sock_closed,
    getfd = sock_getfd,
    bind = sock_bind,
    connect = sock_connect,
    listen = sock_listen,
    getsockname = sock_getsockname,
    setoption = sock_setoption,
    getoption = sock_getoption
}

local dgram_methods = {
    close = sock_close,
    closed = sock_closed,
    getfd = sock_getfd,
    recv = sock_recv,
    send = sock_send,
    recvfrom = sock_recvfrom,
    sendto = sock_sendto,
    bind = sock_bind,
    connect = sock_connect,
    getsockname = sock_getsockname,
    getpeername = sock_getpeername,
    setoption = sock_setoption,
    getoption = sock_getoption
}

local function create_socket(family, typ, protocol, methods, name)
    local fd, err = socket.socket(family, typ, protocol)
    if not fd then
        return nil, 'create socket: ' .. sys.strerror(err)
    end

    return sock_setmetatable(fd, family, typ, methods, name)
end

function M.tcp()
    return create_socket(socket.AF_INET, socket.SOCK_STREAM, 0, stream_methods, SOCK_MT_STREAM)
end

function M.tcp6()
    return create_socket(socket.AF_INET6, socket.SOCK_STREAM, 0, stream_methods, SOCK_MT_STREAM)
end

function M.unix()
    return create_socket(socket.AF_UNIX, socket.SOCK_STREAM, 0, stream_methods, SOCK_MT_STREAM)
end

function M.udp()
    return create_socket(socket.AF_INET, socket.SOCK_DGRAM, 0, dgram_methods, SOCK_MT_DGRAM)
end

function M.udp6()
    return create_socket(socket.AF_INET6, socket.SOCK_DGRAM, 0, dgram_methods, SOCK_MT_DGRAM)
end

function M.icmp()
    return create_socket(socket.AF_INET, socket.SOCK_DGRAM, 1, dgram_methods, SOCK_MT_DGRAM)
end

function M.unix_dgram()
    return create_socket(socket.AF_UNIX, socket.SOCK_DGRAM, 0, dgram_methods, SOCK_MT_DGRAM)
end

function M.listen_unix(path, backlog)
    local sock, err = M.unix()
    if not sock then
        return nil, err
    end

    local ok, err = sock:bind(path)
    if not ok then
        return nil, 'bind: ' .. err
    end

    ok, err = sock:listen(backlog)
    if not ok then
        return nil, 'listen: ' .. err
    end

    return sock
end

local function listen_tcp_common(create, ipaddr, port, backlog)
    local sock, err = create()
    if not sock then
        return nil, err
    end

    sock:setoption('reuseaddr', true)

    local ok, err = sock:bind(ipaddr, port)
    if not ok then
        return nil, 'bind: ' .. err
    end

    ok, err = sock:listen(backlog)
    if not ok then
        return nil, 'listen: ' .. err
    end

    return sock
end

function M.listen_tcp(ipaddr, port, backlog)
    return listen_tcp_common(M.tcp, ipaddr, port, backlog)
end

function M.listen_tcp6(ipaddr, port, backlog)
    return listen_tcp_common(M.tcp6, ipaddr, port, backlog)
end

function M.connect_unix(server_path, local_path)
    local sock, err = M.unix()
    if not sock then
        return nil, err
    end

    local ok, err

    if local_path then
        ok, err = sock:bind(local_path)
        if not ok then
            return nil, 'bind: ' .. err
        end
    end

    ok, err = sock:connect(server_path)
    if not ok then
        return nil, 'connect: ' .. err
    end

    return sock
end

local function connect_tcp_common(create, ipaddr, port)
    local sock, err = create()
    if not sock then
        return nil, err
    end

    local ok, err = sock:connect(ipaddr, port)
    if not ok then
        return nil, 'connect: ' .. err
    end

    return sock
end

function M.connect_tcp(ipaddr, port)
    return connect_tcp_common(M.tcp, ipaddr, port)
end

function M.connect_tcp6(ipaddr, port)
    return connect_tcp_common(M.tcp6, ipaddr, port)
end

return setmetatable(M, { __index = socket })
