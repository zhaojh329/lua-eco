-- SPDX-License-Identifier: MIT
-- Author: Jianhui Zhao <zhaojh329@gmail.com>

local socket = require 'eco.core.socket'
local file = require 'eco.core.file'
local sys = require 'eco.core.sys'
local bufio = require 'eco.bufio'

local sendfile = file.sendfile
local write = file.write

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
    local send

    if family == socket.AF_INET then
        send = socket.sendto
    elseif family == socket.AF_INET6 then
        send = socket.sendto6
    elseif family == socket.AF_UNIX then
        send = socket.sendto_unix
    elseif family == socket.AF_NETLINK then
        send = socket.sendto_nl
    else
        error('invalid family: ' .. family)
    end

    return send(mt.fd, data, ...)
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
    local bind

    if family == socket.AF_INET then
        bind = socket.bind
    elseif family == socket.AF_INET6 then
        bind = socket.bind6
    elseif family == socket.AF_UNIX then
        bind = socket.bind_unix
    elseif family == socket.AF_NETLINK then
        bind = socket.bind_nl
    else
        error('invalid family: ' .. family)
    end

    local ok, err = bind(mt.fd, ...)
    if not ok then
        return nil, sys.strerror(err)
    end

    return true
end

local function sock_update_mt(sock, methods, name)
    local mt = getmetatable(sock)
    mt.name = name
    mt.__index = methods

    if name == SOCK_MT_SERVER then
        mt.iow = nil
    else
        mt.b = bufio.new({ w = mt.ior, is_socket = true })
    end
end

local function sock_setmetatable(fd, family, typ, methods, name)
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
        mt.b = bufio.new({ w = mt.ior, is_socket = true })
    end

    return setmetatable({}, mt)
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
    local connect

    if family == socket.AF_INET then
        connect = socket.connect
    elseif family == socket.AF_INET6 then
        connect = socket.connect6
    elseif family == socket.AF_UNIX then
        connect = socket.connect_unix
    elseif family == socket.AF_NETLINK then
        connect = socket.connect_nl
    else
        error('invalid family: ' .. family)
    end

    local ok, err = connect(mt.fd, ...)
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
        return nil, sys.strerror(err)
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

function M.netlink(protocol)
    return create_socket(socket.AF_NETLINK, socket.SOCK_RAW, protocol, dgram_methods, SOCK_MT_DGRAM)
end

function M.listen_unix(path, options)
    local sock, err = M.unix()
    if not sock then
        return nil, err
    end

    options = options or {}

    local ok, err = sock:bind(path)
    if not ok then
        return nil, err
    end

    ok, err = sock:listen(options.backlog)
    if not ok then
        return nil, err
    end

    return sock
end

local function listen_tcp_common(create, ipaddr, port, options)
    local sock, err = create()
    if not sock then
        return nil, err
    end

    options = options or {}

    if options.reuseaddr then
        sock:setoption('reuseaddr', true)
    end

    if options.reuseport then
        sock:setoption('reuseport', true)
    end

    if options.ipv6_v6only then
        sock:setoption('ipv6_v6only', true)
    end

    local ok, err = sock:bind(ipaddr, port)
    if not ok then
        return nil, err
    end

    ok, err = sock:listen(options.backlog)
    if not ok then
        return nil, err
    end

    return sock
end

function M.listen_tcp(ipaddr, port, options)
    return listen_tcp_common(M.tcp, ipaddr, port, options)
end

function M.listen_tcp6(ipaddr, port, options)
    return listen_tcp_common(M.tcp6, ipaddr, port, options)
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
            return nil, err
        end
    end

    ok, err = sock:connect(server_path)
    if not ok then
        return nil, err
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
        return nil, err
    end

    return sock
end

function M.connect_tcp(ipaddr, port)
    return connect_tcp_common(M.tcp, ipaddr, port)
end

function M.connect_tcp6(ipaddr, port)
    return connect_tcp_common(M.tcp6, ipaddr, port)
end

function M.is_ip_address(addr)
    return socket.is_ipv4_address(addr) or socket.is_ipv6_address(addr)
end

return setmetatable(M, { __index = socket })
