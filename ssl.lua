-- SPDX-License-Identifier: MIT
-- Author: Jianhui Zhao <zhaojh329@gmail.com>

--- SSL/TLS support.
--
-- This module provides TLS-enabled stream connections on top of
-- @{eco.socket} TCP sockets.
--
-- @module eco.ssl

local socket = require 'eco.socket'
local ssl = require 'eco.internal.ssl'
local file = require 'eco.file'
local sync = require 'eco.sync'
local eco = require 'eco'

local M = {}

local function set_ssl_opt(ctx, options)
    local ca = options.ca
    local cert = options.cert
    local key = options.key

    if ca and not ctx:load_ca_cert_file(ca) then
        return nil, 'load ca file fail'
    end

    if cert and not ctx:load_cert_file(cert) then
        return nil, 'load cert file fail'
    end

    if key and not ctx:load_key_file(key) then
        return nil, 'load key file fail'
    end

    return true
end

--- SSL client object.
--
-- Instances are returned by @{connect} or @{ssl_server:accept}.
--
-- @type ssl_client
local cli_methods = {}

--- Send data.
--
-- @function ssl_client:send
-- @tparam string data Data to send.
-- @tparam[opt] number timeout Timeout in seconds
-- @treturn integer Bytes sent.
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
function cli_methods:send(data, timeout)
    local mutex = self.mutex

    mutex:lock()
    local sent, err = self.wr:write(data, timeout)
    mutex:unlock()

    if sent then
        return sent
    else
        return nil, err
    end
end

--- Alias of @{ssl_client:send}.
-- @function ssl_client:write
function cli_methods:write(data, timeout)
    return self:send(data, timeout)
end

--- Send file content.
--
-- This is a convenience helper that reads from a file and sends exactly
-- `len` bytes (unless EOF/error occurs).
--
-- @function ssl_client:sendfile
-- @tparam string path File path.
-- @tparam integer len Bytes to send.
-- @tparam[opt] int offset Start offset in file.
-- @tparam[opt] number timeout Timeout in seconds
-- @treturn integer Bytes sent.
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
function cli_methods:sendfile(path, len, offset, timeout)
    local f<close>, err = file.open(path)
    if not f then
        return nil, err
    end

    if offset then
        f:lseek(offset, file.SEEK_SET)
    end

    local chunk = 4096
    local sent = 0
    local data

    while len > 0 do
        data, err = f:read(chunk > len and len or chunk)
        if not data then
            break
        end

        _, err = self:send(data, timeout)
        if err then
            break
        end

        sent = sent + #data
        len = len - #data
    end

    if not err or err == 'eof' then
        return sent
    end

    return nil, err
end

--- Alias of @{ssl_client:read}.
-- @function ssl_client:recv
function cli_methods:recv(n, timeout)
    return self:read(n, timeout)
end

--- See @{eco.reader:read}
-- @function ssl_client:read
function cli_methods:read(format, timeout)
    return self.rd:read(format, timeout)
end

--- See @{eco.reader:readfull}
-- @function ssl_client:readfull
function cli_methods:readfull(format, timeout)
    return self.rd:readfull(format, timeout)
end

--- See @{eco.reader:readuntil}
-- @function ssl_client:readuntil
function cli_methods:readuntil(format, timeout)
    return self.rd:readuntil(format, timeout)
end

--- Close the TLS connection.
--
-- Frees internal TLS state and closes the underlying TCP socket.
--
-- @function ssl_client:close
function cli_methods:close()
    if self.closed then
        return
    end

    self.closed = true

    -- Wake any blocked read/write coroutine before releasing ssl session.
    self.rd:cancel()
    self.wr:cancel()

    self.sock:close()
    self.ssock:free()

    if not self.keep_ctx and self.ctx then
        self.ctx:free()
    end
end

--- End of `ssl_client` class section.
-- @section end

local cli_metatable = {
    __index = cli_methods,
    __gc = cli_methods.close,
    __close = cli_methods.close
}

--- SSL server listener.
--
-- Instances are returned by @{listen}.
--
-- @type ssl_server
local srv_methods = {}

--- Close the server and free its TLS context.
--
-- @function ssl_server:close
function srv_methods:close()
    if self.closed then
        return
    end

    self.closed = true

    self.ctx:free()
    self.sock:close()
end

local function ssl_handshake(ssock, sock)
    local timeout = 15.0

    while true do
        local ret, err = ssock:handshake()
        if not ret then
            return nil, err
        end

        if ret == true then
            return true
        end

        if ret == ssl.SSL_WANT_READ then
            ret, err = sock.rd:wait(timeout)
        else
            ret, err = sock.wr:wait(timeout)
        end
        if not ret then
            return nil, err
        end
    end
end

local function create_ssl_client(sock, ssock, ctx, keep_ctx)
    local ssock_ptr = ssock:pointer()
    local fd = sock:getfd()

    local rd = eco.reader(fd, ssl.read, ssock_ptr)
    local wr = eco.writer(fd, ssl.write, ssock_ptr)

    return setmetatable({
        ctx = ctx,
        sock = sock,
        ssock = ssock,
        rd = rd,
        wr = wr,
        keep_ctx = keep_ctx,
        mutex = sync.mutex()
    }, cli_metatable)
end

--- Accept a TLS client.
--
-- This accepts an incoming TCP connection and then performs a TLS handshake.
--
-- @function ssl_server:accept
-- @treturn ssl_client Accepted TLS client.
-- @treturn table Peer address table.
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
function srv_methods:accept()
    local sock, peer = self.sock:accept()
    if not sock then
        return nil, peer
    end

    local ssock, err = self.ctx:new(sock:getfd(), self.insecure)
    if not ssock then
        sock:close()
        return nil, err
    end

    local ok
    ok, err = ssl_handshake(ssock, sock)
    if not ok then
        ssock:free()
        sock:close()
        return nil, err
    end

    return create_ssl_client(sock, ssock, nil), peer
end

--- End of `ssl_server` class section.
-- @section end

local srv_metatable = {
    __index = srv_methods,
    __gc = srv_methods.close,
    __close = srv_methods.close
}

--- Create a TLS server listener.
--
-- Internally this calls @{eco.socket.listen_tcp} and wraps accepted sockets
-- with TLS using a server context.
--
-- `options` fields used by TLS:
--
-- - `ca`: Path to CA certificate file.
-- - `cert`: Path to server certificate file.
-- - `key`: Path to server private key file.
-- - `insecure`: When true, disables/relaxes peer verification (backend dependent).
--
-- Other fields are passed to @{eco.socket.listen_tcp}.
--
-- @function listen
-- @tparam string ipaddr Listen address.
-- @tparam integer port Listen port.
-- @tparam[opt] table options Options table.
-- @treturn ssl_server
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
function M.listen(ipaddr, port, options)
    options = options or {}

    local sock, err = socket.listen_tcp(ipaddr, port, options)
    if not sock then
        return nil, err
    end

    local ctx = ssl.context(true)

    local ok, err = set_ssl_opt(ctx, options)
    if not ok then
        sock:close()
        ctx:free()
        return nil, err
    end

    return setmetatable({ ctx = ctx, sock = sock, insecure = options.insecure }, srv_metatable)
end

--- Create a TLS client connection.
--
-- Internally this calls @{eco.socket.connect_tcp} and performs a TLS handshake.
--
-- `options` fields used by TLS:
--
-- - `ca`: Path to CA certificate file.
-- - `cert`: Path to client certificate file (optional, for mTLS).
-- - `key`: Path to client private key file (optional, for mTLS).
-- - `insecure`: When true, disables/relaxes peer verification (backend dependent).
-- - `server_name`: SNI server name.
-- - `ctx`: An existing ssl context object to reuse.
--
-- Other fields are passed to @{eco.socket.connect_tcp}.
--
-- If `options.ctx` is provided, it is reused and will NOT be freed when the
-- returned client is closed.
--
-- @function connect
-- @tparam string ipaddr Remote address.
-- @tparam integer port Remote port.
-- @tparam[opt] table options Options table.
-- @treturn ssl_client
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
function M.connect(ipaddr, port, options)
    options = options or {}

    local sock, err = socket.connect_tcp(ipaddr, port, options)
    if not sock then
        return nil, err
    end

    local ctx = options.ctx
    local keep_ctx = false

    if not ctx then
        ctx = ssl.context()
        local ok, err = set_ssl_opt(ctx, options or {})
        if not ok then
            sock:close()
            ctx:free()
            return nil, err
        end
    else
        keep_ctx = true
    end

    local ssock
    ssock, err = ctx:new(sock:getfd(), options.insecure)
    if not ssock then
        if not keep_ctx then
            ctx:free()
        end
        sock:close()
        return nil, err
    end

    if options.server_name then
        ssock:set_server_name(options.server_name)
    end

    local ok, err = ssl_handshake(ssock, sock)
    if not ok then
        ssock:free()
        if not keep_ctx then
            ctx:free()
        end
        sock:close()
        return nil, err
    end

    return create_ssl_client(sock, ssock, ctx, keep_ctx)
end

return setmetatable(M, { __index = ssl })
