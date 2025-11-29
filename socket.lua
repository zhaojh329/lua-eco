-- SPDX-License-Identifier: MIT
-- Author: Jianhui Zhao <zhaojh329@gmail.com>

local socket = require 'eco.internal.socket'
local sync = require 'eco.sync'
local eco = require 'eco'

local M = {}

local methods = {}

function methods:getfd()
    return self.sock:getfd()
end

function methods:close()
    self.sock:close()
end

function methods:closed()
    return self.sock:closed()
end

function methods:setoption(name, value)
    return self.sock:setoption(name, value)
end

function methods:getsockname()
    return self.sock:getsockname()
end

function methods:getpeername()
    return self.sock:getpeername()
end

function methods:bind(...)
    local ok, err = self.sock:bind(...)
    if not ok then
        return nil, err
    end

    return self
end

function methods:listen(backlog)
    local ok, err = self.sock:listen(backlog)
    if not ok then
        return nil, err
    end

    return self
end

function methods:connect(...)
    local ok, err = self.sock:connect(...)
    if not ok then
        if ok == false then
            ok, err = self.io:wait(eco.WRITE, 5.0)
            if not ok then
                return nil, err
            end

            err = self.sock:getoption('error')
            if err then
                return nil, err
            end

            return self
        end

        return nil, err
    end

    return self
end

local metatable = {
    __index = methods,
    __close = methods.close
}

function methods:accept()
    local ok, err = self.io:wait(eco.READ)
    if not ok then
        return nil, err
    end

    local sock, perr = self.sock:accept()
    if not sock then
        return nil, perr
    end

    local fd = sock:getfd()

    return setmetatable({
        sock = sock,
        domain = self.domain,
        mutex = sync.mutex(),
        rd = eco.reader(fd),
        wr = eco.writer(fd),
        io = eco.io(fd)
    }, metatable), perr
end

function methods:send(data)
    local mutex = self.mutex

    mutex:lock()
    local sent, err = self.wr:write(data)
    mutex:unlock()

    if sent then
        return sent
    else
        return nil, err
    end
end

function methods:write(data)
    return self:send(data)
end

function methods:sendto(data, ...)
    local mutex = self.mutex
    local total = #data

    mutex:lock()

    while #data > 0 do
        self.io:wait(eco.WRITE)

        local sent, err = self.sock:sendto(data, ...)
        if not sent then
            return nil, err
        end

        data = data:sub(sent + 1)
    end

    mutex:unlock()

    return total
end

function methods:sendfile(path, len, offset)
    local mutex = self.mutex

    mutex:lock()
    local sent, err = self.wr:sendfile(path, offset or 0, len)
    mutex:unlock()

    if sent then
        return sent
    end

    return nil, err
end

function methods:recv(n, timeout)
    return self:read(n, timeout)
end

function methods:read(n, timeout)
    return self.rd:read(n, timeout)
end

function methods:read2b(b, n, timeout)
    return self.rd:read2b(b, n, timeout)
end

function methods:recvfrom(n, timeout)
    local ok, err = self.io:wait(eco.READ, timeout)
    if not ok then
        return nil, err
    end

    return self.sock:recvfrom(n)
end

local function socket_init(sock, domain, options)
    local fd = sock:getfd()
    local o = {
        sock = sock,
        domain = domain,
        mutex = sync.mutex(),
        io = eco.io(fd),
        rd = eco.reader(fd),
        wr = eco.writer(fd)
    }

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

    if options.mark then
        sock:setoption('mark', options.mark)
    end

    if options.device then
        sock:setoption('bindtodevice', options.device)
    end

    return setmetatable(o, metatable)
end

function M.socket(family, domain, protocol, options)
    local sock, err = socket.socket(family, domain, protocol)
    if not sock then
        return nil, err
    end

    return socket_init(sock, domain, options)
end

function M.socketpair(family, domain, protocol, options)
    local sock1, sock2 = socket.socketpair(family, domain, protocol)
    if not sock1 then
        return nil, sock2
    end

    return socket_init(sock1, domain, options), socket_init(sock2, domain, options)
end

function M.tcp()
    return M.socket(socket.AF_INET, socket.SOCK_STREAM)
end

function M.tcp6()
    return M.socket(socket.AF_INET6, socket.SOCK_STREAM)
end

function M.udp()
    return M.socket(socket.AF_INET, socket.SOCK_DGRAM)
end

function M.udp6()
    return M.socket(socket.AF_INET6, socket.SOCK_DGRAM)
end

function M.icmp()
    return M.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_ICMP)
end

function M.icmp6()
    return M.socket(socket.AF_INET6, socket.SOCK_DGRAM, socket.IPPROTO_ICMPV6)
end

function M.unix()
    return M.socket(socket.AF_UNIX, socket.SOCK_STREAM)
end

function M.unix_dgram()
    local sock, err = M.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
    if not sock then
        return nil, err
    end

    return sock
end

function M.netlink(protocol)
    return M.socket(socket.AF_NETLINK, socket.SOCK_RAW, protocol)
end

function M.listen_tcp(ipaddr, port, options)
    options = options or {}

    local family = options.ipv6 and socket.AF_INET6 or socket.AF_INET

    local sock, err = M.socket(family, socket.SOCK_STREAM, nil, options)
    if not sock then
        return nil, err
    end

    if options.tcp_nodelay then
        sock:setoption('tcp_nodelay', true)
    end

    if options.keepalive then
        sock:setoption('keepalive', true)
    end

    if options.tcp_keepidle then
        sock:setoption('tcp_keepidle', options.tcp_keepidle)
    end

    if options.tcp_keepcnt then
        sock:setoption('tcp_keepcnt', options.tcp_keepcnt)
    end

    if options.tcp_keepintvl then
        sock:setoption('tcp_keepintvl', options.tcp_keepintvl)
    end

    if options.tcp_fastopen then
        sock:setoption('tcp_fastopen', options.tcp_fastopen)
    end

    _, err = sock:bind(ipaddr, port)
    if err then
        return nil, err
    end

    return sock:listen(options.backlog)
end

local function ipaddr_to_family(ipaddr)
    if socket.is_ipv4_address(ipaddr) then
        return socket.AF_INET
    elseif socket.is_ipv6_address(ipaddr) then
        return socket.AF_INET6
    else
        return nil
    end
end

function M.connect_tcp(ipaddr, port, options)
    options = options or {}

    local family = ipaddr_to_family(ipaddr)

    assert(family, 'not a valid IP address')

    local sock, err = M.socket(family, socket.SOCK_STREAM, nil, options)
    if not sock then
        return nil, err
    end

    return sock:connect(ipaddr, port)
end

function M.listen_udp(ipaddr, port, options)
    options = options or {}

    local family = options.ipv6 and socket.AF_INET6 or socket.AF_INET

    local sock, err = M.socket(family, socket.SOCK_DGRAM, nil, options)
    if not sock then
        return nil, err
    end

    return sock:bind(ipaddr, port)
end

function M.connect_udp(ipaddr, port, options)
    options = options or {}

    local family = ipaddr_to_family(ipaddr)

    assert(family, 'not a valid IP address')

    local sock, err = M.socket(family, socket.SOCK_DGRAM, nil, options)
    if not sock then
        return nil, err
    end

    return sock:connect(ipaddr, port)
end

function M.listen_unix(path, options)
    local sock, err = M.unix()
    if not sock then
        return nil, err
    end

    options = options or {}

    _, err = sock:bind(path)
    if err then
        return nil, err
    end

    return sock:listen(options.backlog)
end

function M.connect_unix(server_path, local_path)
    local sock, err = M.unix()
    if not sock then
        return nil, err
    end

    if local_path then
        _, err = sock:bind(local_path)
        if err then
            return nil, err
        end
    end

    return sock:connect(server_path)
end

function M.is_ip_address(addr)
    return socket.is_ipv4_address(addr) or socket.is_ipv6_address(addr)
end

return setmetatable(M, { __index = socket })
