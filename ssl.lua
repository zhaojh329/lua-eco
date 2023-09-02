-- SPDX-License-Identifier: MIT
-- Author: Jianhui Zhao <zhaojh329@gmail.com>

local file = require 'eco.core.file'
local socket = require 'eco.socket'
local essl = require 'eco.core.ssl'
local sys = require 'eco.core.sys'
local bufio = require 'eco.bufio'

local str_sub = string.sub
local concat = table.concat
local type = type

local SSL_MT_SERVER = 0
local SSL_MT_CLIENT = 1
local SSL_MT_ESTAB  = 2

local M = {}

local function ssl_close(ssock)
    local mt = getmetatable(ssock)

    if mt.closed then
        return
    end

    mt.ssl:free()

    if mt.name ~= SSL_MT_ESTAB then
        mt.ctx:free()
    end

    mt.sock:close()
    mt.closed = true
end

local function ssl_socket(ssock)
    return getmetatable(ssock).sock
end

local client_methods = {
    close = ssl_close,
    socket = ssl_socket
}

function client_methods:closed()
    return getmetatable(self).closed
end

function client_methods:send(data)
    local mt = getmetatable(self)

    if mt.closed then
        return nil, 'closed'
    end

    local ssl, iow, ior = mt.ssl, mt.iow, mt.ior
    local w = iow

    local total = #data
    local sent = 0
    local ok, n, err, errs

    while sent < total do
        ok, err = w:wait()
        if not ok then
            return nil, err, sent
        end

        n, err, errs = ssl:write(str_sub(data, sent + 1))
        if not n then
            if err == essl.ERROR then
                return nil, errs, sent
            end

            w = err == essl.WANT_READ and ior or iow
        end
        sent = sent + n
    end

    return sent
end

function client_methods:sendfile(fd, count, offset)
    local mt = getmetatable(self)

    if mt.closed then
        return nil, 'closed'
    end

    local st, err = file.fstat(fd)
    if not st then
        return false, err
    end

    count = count or st.size

    if offset then
        offset, err = file.lseek(fd, offset, file.SEEK_SET)
        if not offset then
            return nil, err
        end
    end

    local chunk = 4096
    local sent = 0
    local data

    while count > 0 do
        data, err = file.read(fd, chunk > count and count or chunk)
        if not data then
            break
        end

        if #data == 0 then
            break
        end

        _, err = self:send(data)
        if err then
            break
        end

        sent = sent + #data
        count = count - #data
    end

    if err then
        return nil, err
    end

    return sent
end

function client_methods:recv(pattern, timeout)
    local mt = getmetatable(self)
    local b = mt.b

    if mt.closed then
        return nil, 'closed'
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

function client_methods:recvfull(size, timeout)
    local mt = getmetatable(self)
    local b = mt.b

    if mt.closed then
        return nil, 'closed'
    end

    if size <= 0 then return '' end

    return b:readfull(size, timeout)
end

function client_methods:discard(size, timeout)
    local mt = getmetatable(self)
    local b = mt.b

    if mt.closed then
        return nil, 'closed'
    end

    if size <= 0 then return 0 end

    return b:discard(size, timeout)
end

local function ssl_wait(err, ior, iow, timeout)
    local w = err == essl.WANT_READ and ior or iow
    return w:wait(timeout)
end

local function ssl_negotiate(mt, deadtime)
    local ssl, iow, ior = mt.ssl, mt.iow, mt.ior
    local ok, err, errs, w

    while true do
        ok, err, errs = ssl:negotiate()
        if ok then
            return true
        end

        if err == essl.ERROR or err == essl.INSECURE then
            return false, errs
        end

        if not ssl_wait(err, ior, iow, deadtime - sys.uptime()) then
            return nil, 'handshake timeout'
        end
    end
end

local function create_bufio(mt)
    local reader = { ssl = mt.ssl, ior = mt.ior, iow = mt.iow }

    function reader:read(n, timeout)
        if not self.ior:wait(timeout) then
            return nil, 'timeout'
        end

        local ssl = self.ssl

        while true do
            local data, err, errs = ssl:read(n)
            if not data then
                if err == essl.ERROR then
                    return nil, errs
                end

                if not ssl_wait(err, self.ior, self.iow, timeout) then
                    return nil, 'timeout'
                end
            else
                if #data == 0 then
                    return nil, 'closed'
                end

                return data
            end
        end
    end

    function reader:read2b(b, timeout)
        if b:room() == 0 then
            return nil, 'buffer is full'
        end

        if not self.ior:wait(timeout) then
            return nil, 'timeout'
        end

        local ssl = self.ssl

        while true do
            local r, err, errs = ssl:read_to_buffer(b)
            if not r then
                if err == essl.ERROR then
                    return nil, errs
                end

                if not ssl_wait(err, self.ior, self.iow, timeout) then
                    return nil, 'timeout'
                end
            else
                if r == 0 then
                    return nil, 'closed'
                end

                return r
            end
        end
    end

    return bufio.new(reader)
end

local function ssl_setmetatable(ctx, sock, methods, name, insecure)
    local ssock = {}

    local fd = sock:getfd()

    local mt = {
        name = name,
        fd = fd,
        ctx = ctx,
        sock = sock,
        ior = eco.watcher(eco.IO, fd),
        __index = methods,
        __gc = methods.close
    }

    setmetatable(ssock, mt)

    if name == SSL_MT_SERVER then
        return ssock
    else
        mt.ssl = ctx:new(fd, insecure)
        mt.iow = eco.watcher(eco.IO, fd, eco.WRITE)
        mt.b = create_bufio(mt)
    end

    local ok, err = ssl_negotiate(mt, sys.uptime() + 3.0)
    if not ok then
        return nil, err
    end

    return ssock
end

local server_methods = {
    close = ssl_close,
    socket = ssl_socket
}

function server_methods:accept()
    local mt = getmetatable(self)

    local sock, addr = mt.sock:accept()
    if not sock then
        return nil, addr
    end

    local ssock, err = ssl_setmetatable(mt.ctx, sock, client_methods, SSL_MT_ESTAB)
    if not ssock then
        return nil, err
    end

    return ssock, addr
end

function M.listen(ipaddr, port, options, ipv6)
    assert(type(options) == 'table' and options.cert and options.key)

    local ctx = essl.context(true)

    if options.ca then
        if not ctx:load_ca_cert_file(options.ca) then
            return nil, 'load ca cert file fail'
        end
    end

    if not ctx:load_cert_file(options.cert) then
        return nil, 'load cert file fail'
    end

    if not ctx:load_key_file(options.key) then
        return nil, 'load key file fail'
    end

    local listen = socket.listen_tcp

    if ipv6 then
        listen = socket.listen_tcp6
    end

    local sock, err = listen(ipaddr, port, options)
    if not sock then
        return nil, err
    end

    return ssl_setmetatable(ctx, sock, server_methods, SSL_MT_SERVER)
end

function M.listen6(ipaddr, port, options)
    return M.listen(ipaddr, port, options, true)
end

local function ssl_connect(ipaddr, port, insecure, ipv6)
    local connect = socket.connect_tcp

    if ipv6 then
        connect = socket.connect_tcp6
    end

    local sock, err = connect(ipaddr, port)
    if not sock then
        return nil, err
    end

    local ctx = essl.context(false)

    return ssl_setmetatable(ctx, sock, client_methods, SSL_MT_CLIENT, insecure)
end

function M.connect(ipaddr, port, insecure)
    return ssl_connect(ipaddr, port, insecure)
end

function M.connect6(ipaddr, port, insecure)
    return ssl_connect(ipaddr, port, insecure, true)
end

return M
