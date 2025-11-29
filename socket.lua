-- SPDX-License-Identifier: MIT
-- Author: Jianhui Zhao <zhaojh329@gmail.com>

--- socket functions.
-- @module eco.socket

local socket = require 'eco.internal.socket'
local sync = require 'eco.sync'
local eco = require 'eco'

local M = {
    --- Address family: unspecified.
    AF_UNSPEC = socket.AF_UNSPEC,
    --- Address family: IPv4.
    AF_INET = socket.AF_INET,
    --- Address family: IPv6.
    AF_INET6 = socket.AF_INET6,
    --- Address family: Unix domain sockets.
    AF_UNIX = socket.AF_UNIX,
    --- Address family: packet interface (link layer).
    AF_PACKET = socket.AF_PACKET,
    --- Address family: netlink.
    AF_NETLINK = socket.AF_NETLINK,

    --- Socket type: datagram.
    SOCK_DGRAM = socket.SOCK_DGRAM,
    --- Socket type: stream.
    SOCK_STREAM = socket.SOCK_STREAM,
    --- Socket type: raw.
    SOCK_RAW = socket.SOCK_RAW,

    --- Protocol number: ICMP (IPv4).
    IPPROTO_ICMP = socket.IPPROTO_ICMP,
    --- Protocol number: ICMPv6.
    IPPROTO_ICMPV6 = socket.IPPROTO_ICMPV6,

    --- Protocol number: TCP.
    IPPROTO_TCP = socket.IPPROTO_TCP,
    --- Protocol number: UDP.
    IPPROTO_UDP = socket.IPPROTO_UDP,
}

--- Socket object returned by this module.
--
-- @type socket
local methods = {}

--- Get underlying file descriptor.
-- @function socket:getfd
-- @treturn int fd
function methods:getfd()
    return self.sock:getfd()
end

--- Close the socket.
-- @function socket:close
function methods:close()
    self.sock:close()
end

--- Check whether the socket is closed.
-- @function socket:closed
-- @treturn boolean
function methods:closed()
    return self.sock:closed()
end

--- Set a socket option.
--
-- Supported option names: `reuseaddr`, `reuseport`, `keepalive`,
-- `broadcast`, `mark`, `bindtodevice`, `tcp_nodelay`, `tcp_keepidle`, ...
--
-- @function socket:setoption
-- @tparam string name Option name.
-- @tparam any value Option value.
-- @treturn boolean true On success.
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
function methods:setoption(name, value)
    return self.sock:setoption(name, value)
end

--- Get local socket address.
--
-- Returned address is a table. Typical fields:
--
-- - `family`
-- - IPv4/IPv6: `ipaddr`, `port`
-- - Unix: `path`
-- - Netlink: `pid`
--
-- @function socket:getsockname
-- @treturn table addr
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
function methods:getsockname()
    return self.sock:getsockname()
end

--- Get peer socket address.
--
-- Address table format is the same as @{socket:getsockname}.
--
-- @function socket:getpeername
-- @treturn table addr
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
function methods:getpeername()
    return self.sock:getpeername()
end

--- Bind to a local address.
--
-- Arguments depend on socket family:
--
-- - IPv4/IPv6: `bind(ipaddr, port)` (`ipaddr` can be nil for ANY)
-- - Unix: `bind(path)`
-- - Netlink: `bind(groups?, pid?)`
-- - Packet: `bind({ ifindex=..., ifname=... })`
--
-- @function socket:bind
-- @treturn socket self
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
function methods:bind(...)
    local ok, err = self.sock:bind(...)
    if not ok then
        return nil, err
    end

    return self
end

--- Start listening (server sockets).
--
-- @function socket:listen
-- @tparam[opt] int backlog Listen backlog.
-- @treturn socket self
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
function methods:listen(backlog)
    local ok, err = self.sock:listen(backlog)
    if not ok then
        return nil, err
    end

    return self
end

--- Connect to a remote address.
--
-- Arguments depend on socket family (same as @{socket:bind}).
--
-- @function socket:connect
-- @treturn socket self
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
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

--- Accept an incoming connection.
--
-- @function socket:accept
-- @treturn socket client Accepted client socket.
-- @treturn socket A new socket object.
-- @treturn table Peer address table.
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
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

--- Send data on a connected stream socket.
--
-- This method serializes concurrent writers using an internal mutex.
--
-- @function socket:send
-- @tparam string data Data to send.
-- @treturn int Bytes sent.
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
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

--- Alias of @{socket:send}.
-- @function socket:write
function methods:write(data)
    return self:send(data)
end

--- Send a datagram.
--
-- For UDP/RAW sockets, destination address is provided after `data`.
-- Arguments follow the same conventions as @{socket:connect}.
--
-- @function socket:sendto
-- @tparam string data
-- @treturn int Total bytes sent.
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
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

--- Send file contents on a connected stream socket.
--
-- @function socket:sendfile
-- @tparam string path File path.
-- @tparam[opt] int len Bytes to send.
-- @tparam[opt=0] int offset File offset.
-- @treturn int Bytes sent.
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
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

--- Alias of @{socket:read}.
-- @function socket:recv
function methods:recv(n, timeout)
    return self:read(n, timeout)
end

--- Read from connected stream socket.
--
-- This calls `eco.reader:read` on the underlying fd.
--
-- @function socket:read
-- @tparam int expected Number of bytes to read (must be > 0).
-- @tparam[opt] number timeout Timeout in seconds.
-- @treturn string Data read from the file descriptor
-- @treturn[2] nil On timeout, EOF, or error.
-- @treturn[2] string Error message.
function methods:read(n, timeout)
    return self.rd:read(n, timeout)
end

--- Read into buffer.
--
-- This calls `eco.reader:read2b` on the underlying fd.
--
-- @function socket:read2b
-- @tparam buffer b An @{eco.buffer} object.
-- @tparam int expected Number of bytes expected to read (cannot be 0).
-- @tparam[opt] number timeout Timeout in seconds.
-- @treturn int bytes Number of bytes actually read.
-- @treturn[2] nil On error or EOF.
-- @treturn[2] string Error message or "eof".
function methods:read2b(b, n, timeout)
    return self.rd:read2b(b, n, timeout)
end

--- Receive a datagram.
--
-- @function socket:recvfrom
-- @tparam int n Max bytes to receive.
-- @tparam[opt] number timeout Timeout in seconds.
-- @treturn string data
-- @treturn table Peer address.
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
function methods:recvfrom(n, timeout)
    local ok, err = self.io:wait(eco.READ, timeout)
    if not ok then
        return nil, err
    end

    return self.sock:recvfrom(n)
end

--- End of `socket` class section.
-- @section end

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

--- Create a socket.
--
-- @function socket
-- @tparam int family Address family (e.g. @{socket.AF_INET}).
-- @tparam int domain Socket type (e.g. @{socket.SOCK_STREAM}).
-- @tparam[opt=0] int protocol Protocol number.
-- @tparam[opt] table options Options:
--
-- - `reuseaddr` (boolean)
-- - `reuseport` (boolean)
-- - `ipv6_v6only` (boolean)
-- - `mark` (int)
-- - `device` (string) bind to device name
--
-- @treturn socket sock
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
function M.socket(family, domain, protocol, options)
    local sock, err = socket.socket(family, domain, protocol)
    if not sock then
        return nil, err
    end

    return socket_init(sock, domain, options)
end

--- Create a pair of connected sockets.
--
-- @function socketpair
-- @tparam int family
-- @tparam int domain
-- @tparam[opt=0] int protocol
-- @tparam[opt] table options See @{socket}.
-- @treturn socket sock1
-- @treturn socket sock2
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
function M.socketpair(family, domain, protocol, options)
    local sock1, sock2 = socket.socketpair(family, domain, protocol)
    if not sock1 then
        return nil, sock2
    end

    return socket_init(sock1, domain, options), socket_init(sock2, domain, options)
end

--- Create a TCP (IPv4) stream socket.
-- @function tcp
-- @treturn socket sock
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
function M.tcp()
    return M.socket(socket.AF_INET, socket.SOCK_STREAM)
end

--- Create a TCP (IPv6) stream socket.
-- @function tcp6
-- @treturn socket sock
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
function M.tcp6()
    return M.socket(socket.AF_INET6, socket.SOCK_STREAM)
end

--- Create a UDP (IPv4) datagram socket.
-- @function udp
-- @treturn socket sock
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
function M.udp()
    return M.socket(socket.AF_INET, socket.SOCK_DGRAM)
end

--- Create a UDP (IPv6) datagram socket.
-- @function udp6
-- @treturn socket sock
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
function M.udp6()
    return M.socket(socket.AF_INET6, socket.SOCK_DGRAM)
end

--- Create an ICMP (IPv4) socket.
-- @function icmp
-- @treturn socket sock
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
function M.icmp()
    return M.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_ICMP)
end

--- Create an ICMP (IPv6) socket.
-- @function icmp6
-- @treturn socket sock
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
function M.icmp6()
    return M.socket(socket.AF_INET6, socket.SOCK_DGRAM, socket.IPPROTO_ICMPV6)
end

--- Create a Unix stream socket.
-- @function unix
-- @treturn socket sock
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
function M.unix()
    return M.socket(socket.AF_UNIX, socket.SOCK_STREAM)
end

--- Create a Unix datagram socket.
-- @function unix_dgram
-- @treturn socket sock
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
function M.unix_dgram()
    local sock, err = M.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
    if not sock then
        return nil, err
    end

    return sock
end

--- Create a netlink raw socket.
-- @function netlink
-- @tparam int protocol Netlink protocol.
-- @treturn socket sock
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
function M.netlink(protocol)
    return M.socket(socket.AF_NETLINK, socket.SOCK_RAW, protocol)
end

--- Create, bind and listen on a TCP socket.
--
-- @function listen_tcp
-- @tparam[opt] string ipaddr Local address (nil means ANY).
-- @tparam int port Local port.
-- @tparam[opt] table options Options:
--
-- - `ipv6` (boolean) use IPv6 family
-- - `backlog` (int)
-- - `tcp_nodelay` (boolean)
-- - `keepalive` (boolean)
-- - `tcp_keepidle` (int)
-- - `tcp_keepcnt` (int)
-- - `tcp_keepintvl` (int)
-- - `tcp_fastopen` (int)
-- - plus options accepted by @{socket}
--
-- @treturn socket sock
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
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

--- Create and connect a TCP socket.
--
-- Address family is inferred from `ipaddr`.
--
-- @function connect_tcp
-- @tparam string ipaddr Remote IPv4/IPv6 address.
-- @tparam int port Remote port.
-- @tparam[opt] table options Options accepted by @{socket}.
-- @treturn socket sock
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
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

--- Create and bind a UDP socket.
--
-- @function listen_udp
-- @tparam[opt] string ipaddr Local address.
-- @tparam int port Local port.
-- @tparam[opt] table options Options (`ipv6` + options accepted by @{socket}).
-- @treturn socket sock
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
function M.listen_udp(ipaddr, port, options)
    options = options or {}

    local family = options.ipv6 and socket.AF_INET6 or socket.AF_INET

    local sock, err = M.socket(family, socket.SOCK_DGRAM, nil, options)
    if not sock then
        return nil, err
    end

    return sock:bind(ipaddr, port)
end

--- Create and connect a UDP socket.
--
-- @function connect_udp
-- @tparam string ipaddr Remote address.
-- @tparam int port Remote port.
-- @tparam[opt] table options Options accepted by @{socket}.
-- @treturn socket sock
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
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

--- Create, bind and listen on a Unix domain socket.
--
-- @function listen_unix
-- @tparam string path Filesystem path.
-- @tparam[opt] table options Options (`backlog` + options accepted by @{socket}).
-- @treturn socket sock
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
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

--- Connect to a Unix domain socket.
--
-- @function connect_unix
-- @tparam string server_path Server socket path.
-- @tparam[opt] string local_path Optional local bind path.
-- @treturn socket sock
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
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

--- Check if a string is an IPv4/IPv6 address.
--
-- @function is_ip_address
-- @tparam string addr Address string.
-- @treturn boolean ok
function M.is_ip_address(addr)
    return socket.is_ipv4_address(addr) or socket.is_ipv6_address(addr)
end

return setmetatable(M, { __index = socket })
