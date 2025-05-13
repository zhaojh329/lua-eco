-- SPDX-License-Identifier: MIT
-- Author: Jianhui Zhao <zhaojh329@gmail.com>

local socket = require 'eco.core.socket'
local bufio = require 'eco.bufio'
local sync = require 'eco.sync'

local M = {}

local methods = {}

function methods:getfd()
    return self.sock:getfd()
end

function methods:close()
    if self.b then
        self.b:close()
    end

    self.sock:close()
end

function methods:closed()
    self.sock:closed()
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
    local sock, err = self.sock:bind(...)
    if not sock then
        return nil, err
    end

    return self
end

function methods:listen(backlog)
    local sock, err = self.sock:listen(backlog)
    if not sock then
        return nil, err
    end

    return self
end

function methods:connect(...)
    local sock, err = self.sock:connect(...)
    if not sock then
        return nil, err
    end

    return self
end

local metatable = {
    __index = methods,
    __close = methods.close
}

function methods:accept()
    local sock, perr = self.sock:accept()
    if not sock then
        return nil, perr
    end

    local b = bufio.new(sock:getfd(), { eof_error = 'closed' })

    return setmetatable({ sock = sock, domain = self.domain, b = b, mutex = sync.mutex() }, metatable), perr
end

function methods:send(data)
    local mutex = self.mutex

    mutex:lock()
    local sent, err = self.sock:send(data)
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
    return self.sock:sendto(data, ...)
end

function methods:sendfile(path, len, offset)
    local mutex = self.mutex

    mutex:lock()
    local sent, err = self.sock:sendfile(path, len, offset)
    mutex:unlock()

    if sent then
        return sent
    else
        return nil, err
    end
end

--[[
  Reads according to the given pattern, which specify what to read.

  In case of success, it returns the data received; in case of error, it returns
  nil with a string describing the error and the partial data received so far.

  The available pattern are:
    'a': reads the whole file or reads from socket until the connection closed.
    'l': reads the next line skipping the end of line character.
    'L': reads the next line keeping the end-of-line character (if present).
    number: reads a string with up to this number of bytes.

  Note: Only `number` is supported for SOCK_DGRAM.
--]]
function methods:recv(pattern, timeout)
    if self.domain == socket.SOCK_STREAM then
        return self.b:read(pattern, timeout)
    else
        return self.sock:recv(pattern, timeout)
    end
end

function methods:read(pattern, timeout)
    return self:recv(pattern, timeout)
end

function methods:recvfull(n, timeout)
    assert(self.domain == socket.SOCK_STREAM)
    return self.b:readfull(n, timeout)
end

function methods:readfull(n, timeout)
    return self:recvfull(n, timeout)
end

function methods:peek(n, timeout)
    assert(self.domain == socket.SOCK_STREAM)
    return self.b:peek(n, timeout)
end

function methods:recvuntil(pattern, timeout)
    assert(self.domain == socket.SOCK_STREAM)
    return self.b:readuntil(pattern, timeout)
end

function methods:readuntil(pattern, timeout)
    return self:recvuntil(pattern, timeout)
end

function methods:discard(n, timeout)
    assert(self.domain == socket.SOCK_STREAM)
    return self.b:discard(n, timeout)
end

function methods:recvfrom(n, timeout)
    return self.sock:recvfrom(n, timeout)
end

function M.socket(family, domain, protocol, options)
    local sock, err = socket.socket(family, domain, protocol)
    if not sock then
        return nil, err
    end

    local o = { sock = sock, domain = domain, mutex = sync.mutex() }

    if domain == socket.SOCK_STREAM then
        o.b = bufio.new(sock:getfd(), { eof_error = 'closed' })
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

    if options.mark then
        sock:setoption('mark', options.mark)
    end

    if options.device then
        sock:setoption('bindtodevice', options.device)
    end

    return setmetatable(o, metatable)
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

    local ok, err = sock:bind(ipaddr, port)
    if not ok then
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

    local ok, err = sock:bind(path)
    if not ok then
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
        local ok, err = sock:bind(local_path)
        if not ok then
            return nil, err
        end
    end

    return sock:connect(server_path)
end

function M.is_ip_address(addr)
    return socket.is_ipv4_address(addr) or socket.is_ipv6_address(addr)
end

return setmetatable(M, { __index = socket })
