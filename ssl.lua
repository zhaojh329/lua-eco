-- SPDX-License-Identifier: MIT
-- Author: Jianhui Zhao <zhaojh329@gmail.com>

local socket = require 'eco.socket'
local ssl = require 'eco.core.ssl'
local bufio = require 'eco.bufio'
local file = require 'eco.file'
local sync = require 'eco.sync'

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

local cli_methods = {}

function cli_methods:set_server_name(name)
    return self.ssock:set_server_name(name)
end

function cli_methods:send(data)
    local mutex = self.mutex

    mutex:lock()
    local sent, err = self.ssock:send(data)
    mutex:unlock()

    if sent then
        return sent
    else
        return nil, err
    end
end

function cli_methods:write(data)
    return self:send(data)
end

function cli_methods:sendfile(path, len, offset)
    local fd, err = file.open(path)
    if not fd then
        return nil, err
    end

    if offset then
        file.lseek(fd, offset, file.SEEK_SET)
    end

    local b = bufio.new(fd)

    local chunk = 4096
    local sent = 0
    local data

    while len > 0 do
        data, err = b:read(chunk > len and len or chunk)
        if not data then
            break
        end

        _, err = self:send(data)
        if err then
            break
        end

        sent = sent + #data
        len = len - #data
    end

    file.close(fd)

    if not err or err == 'eof' then
        return sent
    end

    return nil, err
end

--[[
  Reads according to the given pattern, which specify what to read.

  In case of success, it returns the data received; in case of error, it returns
  nil with a string describing the error.

  The available pattern are:
    'a': reads the whole file or reads from socket until the connection closed.
    'l': reads the next line skipping the end of line character.
    'L': reads the next line keeping the end-of-line character (if present).
    number: reads a string with up to this number of bytes.
--]]
function cli_methods:recv(pattern, timeout)
    return self.b:read(pattern, timeout)
end

function cli_methods:read(pattern, timeout)
    return self:recv(pattern, timeout)
end

function cli_methods:recvfull(n, timeout)
    return self.b:readfull(n, timeout)
end

function cli_methods:readfull(n, timeout)
    return self:recvfull(n, timeout)
end

function cli_methods:peek(n, timeout)
    return self.b:peek(n, timeout)
end

function cli_methods:recvuntil(pattern, timeout)
    return self.b:readuntil(pattern, timeout)
end

function cli_methods:readuntil(pattern, timeout)
    return self:recvuntil(pattern, timeout)
end

function cli_methods:discard(n, timeout)
    return self.b:discard(n, timeout)
end

function cli_methods:close()
    self.b:close()
    self.ssock:free()

    if not self.keep_ctx and self.ctx then
        self.ctx:free()
    end

    self.sock:close()
end

local cli_metatable = {
    __index = cli_methods,
    __gc = cli_methods.close,
    __close = cli_methods.close
}

local srv_methods = {}

function srv_methods:close()
    self.ctx:free()
    self.sock:close()
end

local function create_ssl_client(sock, ssock, ctx, keep_ctx)
    local b = bufio.new(
        sock:getfd(), {
        eof_error = 'closed',
        fill = ssl.bufio_fill,
        ctx = ssock:pointer()
    })
    return setmetatable({
        ctx = ctx,
        sock = sock,
        ssock = ssock,
        b = b,
        keep_ctx = keep_ctx,
        mutex = sync.mutex()
    }, cli_metatable)
end

function srv_methods:accept()
    local sock, peer = self.sock:accept()
    if not sock then
        return nil, peer
    end

    local ssock = self.ctx:new(sock:getfd(), self.insecure)

    local ok, err = ssock:handshake()
    if not ok then
        ssock:free()
        sock:close()
        return nil, err
    end

    return create_ssl_client(sock, ssock, nil), peer
end

local srv_metatable = {
    __index = srv_methods,
    __gc = srv_methods.close,
    __close = srv_methods.close
}

function M.listen(ipaddr, port, options)
    options = options or {}

    local sock, err = socket.listen_tcp(ipaddr, port, options)
    if not sock then
        return nil, err
    end

    sock.b = nil

    local ctx = ssl.context(true)

    local ok, err = set_ssl_opt(ctx, options)
    if not ok then
        sock:close()
        ctx:free()
        return nil, err
    end

    return setmetatable({ ctx = ctx, sock = sock, insecure = options.insecure }, srv_metatable)
end

function M.connect(ipaddr, port, options)
    options = options or {}

    local sock, err = socket.connect_tcp(ipaddr, port, options)
    if not sock then
        return nil, err
    end

    sock.b = nil

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

    local ssock = ctx:new(sock:getfd(), options.insecure)

    local ok, err = ssock:handshake()
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
