-- SPDX-License-Identifier: MIT
-- Author: Jianhui Zhao <zhaojh329@gmail.com>

local socket = require 'eco.core.socket'
local file = require 'eco.core.file'
local sys = require 'eco.core.sys'

local sendfile = file.sendfile
local write = file.write

local SOCK_MT_STREAM = 0
local SOCK_MT_DGRAM  = 1
local SOCK_MT_SERVER = 2
local SOCK_MT_CLIENT = 3
local SOCK_MT_ESTAB  = 4

local M = {}

local function sock_getsockname(self)
    return socket.getsockname(self.fd)
end

local function sock_getpeername(self)
    return socket.getpeername(self.fd)
end

-- Set the timeout value in seconds for subsequent socket operations
local function sock_settimeout(self, seconds)
    self.timeout = seconds
end

local function sock_getfd(self)
    return self.fd
end

local function sock_setoption(self, ...)
    local fd = sock_getfd(self)
    return socket.setoption(fd, ...)
end

local function sock_getoption(self, ...)
    local fd = sock_getfd(self)
    return socket.getoption(fd, ...)
end

local function sock_close(self)
    local fd = self.fd

    if fd < 0 then
        return
    end

    if self.name ~= SOCK_MT_ESTAB then
        local addr = socket.getsockname(fd)
        if addr and addr.family == socket.AF_UNIX then
            if addr.path and file.access(addr.path) then
                os.remove(addr.path)
            end
        end
    end

    file.close(fd)
    self.fd = -1
end

local function sock_closed(self)
    return sock_getfd(self) < 0
end

local function sock_recv(self, n)
    local fd = self.fd

    if fd < 0 then
        return nil, 'closed'
    end

    if not self.ior:wait(self.timeout) then
        return nil, 'timeout'
    end

    local data, err = socket.recv(fd, n)
    if not data then
        return nil, err
    end

    if #data == 0 then
        return nil, 'closed'
    end

    return data
end

local function sock_send(self, data)
    if self:closed() then
        return nil, 'closed'
    end

    local iow = self.iow
    local fd = self.fd
    local total = #data
    local sent = 0
    local ok, n, err

    while sent < total do
        ok, err = iow:wait()
        if not ok then
            return nil, err, sent
        end

        n, err = write(fd, data:sub(sent + 1))
        if not n then
            return nil, err, sent
        end
        sent = sent + n
    end

    return sent
end

local function sock_sendfile(self, fd, count, offset)
    if self:closed() then
        return nil, 'closed'
    end

    local iow = self.iow
    local sfd = self.fd
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

local function sock_recvfrom(self, n)
    if self:closed() then
        return nil, 'closed'
    end

    if not self.ior:wait(self.timeout) then
        return nil, 'timeout'
    end

    return socket.recvfrom(self.fd, n)
end

local function sock_sendto(self, data, ...)
    if self:closed() then
        return nil, 'closed'
    end

    local family = self.family
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

    return send(self.fd, data, ...)
end

local client_methods = {
    close = sock_close,
    closed = sock_closed,
    getfd = sock_getfd,
    recv = sock_recv,
    send = sock_send,
    sendfile = sock_sendfile,
    getsockname = sock_getsockname,
    getpeername = sock_getpeername,
    setoption = sock_setoption,
    getoption = sock_getoption,
    settimeout = sock_settimeout
}

local client_mt = {
    __index = client_methods,
    __gc = sock_close
}

local function sock_bind(self, ...)
    local family = self.family
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

    local ok, err = bind(self.fd, ...)
    if not ok then
        return nil, sys.strerror(err)
    end

    return true
end

local function sock_update_mt(self, mt, name)
    self.name = name

    if name == SOCK_MT_SERVER then
        self.iow = nil
    end

    setmetatable(self, mt)
end

local function sock_setmetatable(fd, family, typ, mt, name)
    local o = {
        name = name,
        family = family,
        typ = typ,
        fd = fd,
        ior = eco.watcher(eco.IO, fd),
        iow = eco.watcher(eco.IO, fd, eco.WRITE)
    }

    return setmetatable(o, mt)
end

local function sock_accept(self)
    if self:closed() then
        return nil, 'closed'
    end

    if not self.ior:wait(self.timeout) then
        return nil, 'timeout'
    end

    local fd, addr = socket.accept(self.fd)
    if not fd then
        return nil, sys.strerror(addr)
    end

    return sock_setmetatable(fd, self.family, self.typ, client_mt, SOCK_MT_ESTAB), addr
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

local server_mt = {
    __index = server_methods,
    __gc = sock_close
}

local function sock_listen(self, backlog)
    local fd = sock_getfd(self)
    local ok, err = socket.listen(fd, backlog)
    if not ok then
        return false, sys.strerror(err)
    end

    sock_update_mt(self, server_mt, SOCK_MT_SERVER)

    return true
end

local function sock_connect_ok(self)
    if self.typ == socket.SOCK_STREAM then
        sock_update_mt(self, client_mt, SOCK_MT_CLIENT)
    end

    return true
end

local function sock_connect(self, ...)
    if self:closed() then
        return false, 'closed'
    end

    local family = self.family
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

    local ok, err = connect(self.fd, ...)
    if not ok then
        if err == sys.EINPROGRESS then
            if not self.iow:wait(3.0) then
                return nil, 'timeout'
            end

            err = socket.getoption(self.fd, 'error')
            if err == 0 then
                return sock_connect_ok(self)
            end
        end
        return false, sys.strerror(err)
    end

    return sock_connect_ok(self)
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
    getoption = sock_getoption,
    settimeout = sock_settimeout
}

local function create_socket(family, typ, protocol, methods, name)
    local fd, err = socket.socket(family, typ, protocol)
    if not fd then
        return nil, sys.strerror(err)
    end

    return sock_setmetatable(fd, family, typ, methods, name)
end

local stream_mt = {
    __index = stream_methods,
    __gc = sock_close
}

local dgram_mt = {
    __index = dgram_methods,
    __gc = sock_close
}

function M.tcp()
    return create_socket(socket.AF_INET, socket.SOCK_STREAM, 0, stream_mt, SOCK_MT_STREAM)
end

function M.tcp6()
    return create_socket(socket.AF_INET6, socket.SOCK_STREAM, 0, stream_mt, SOCK_MT_STREAM)
end

function M.unix()
    return create_socket(socket.AF_UNIX, socket.SOCK_STREAM, 0, stream_mt, SOCK_MT_STREAM)
end

function M.udp()
    return create_socket(socket.AF_INET, socket.SOCK_DGRAM, 0, dgram_mt, SOCK_MT_DGRAM)
end

function M.udp6()
    return create_socket(socket.AF_INET6, socket.SOCK_DGRAM, 0, dgram_mt, SOCK_MT_DGRAM)
end

function M.icmp()
    return create_socket(socket.AF_INET, socket.SOCK_DGRAM, 1, dgram_mt, SOCK_MT_DGRAM)
end

function M.unix_dgram()
    return create_socket(socket.AF_UNIX, socket.SOCK_DGRAM, 0, dgram_mt, SOCK_MT_DGRAM)
end

function M.netlink(protocol)
    return create_socket(socket.AF_NETLINK, socket.SOCK_RAW, protocol, dgram_mt, SOCK_MT_DGRAM)
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
