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

local socket = require 'eco.socket'
local buffer = require 'eco.buffer'
local ssl = require 'eco.core.ssl'
local time = require 'eco.time'

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

local client_methods = {
    close = ssl_close
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
    local ok, n, err

    while sent < total do
        ok, err = w:wait()
        if not ok then
            return nil, err, sent
        end

        n, err = ssl:write(data:sub(sent + 1))
        if not n then
            if err then
                return nil, err, sent
            end
            if ssl:state() == -2 then
                w = ior
            else
                w = iow
            end
        end
        sent = sent + n
    end

    return sent
end

--[[
    Reads data from a socket, according to the specified read pattern.
    '*l': reads a line of text from the socket. The line is terminated by a LF character (ASCII 10).
          The LF characters are not included in the returned line.
    '*L': Works exactly as the '*l' pattern but the LF characters are included in the returned line.
    number: read a specified number of bytes from the socket.

    If successful, the method returns the received pattern. In case of error, the method returns nil
    followed by an error message, followed by a (possibly empty) string containing the partial that
    was received. The error message can be the string 'closed' in case the connection was closed
    before the transmission was completed or the string 'timeout' in case there was a timeout during
    the operation.
--]]
function client_methods:recv(pattern, timeout)
    local mt = getmetatable(self)

    if mt.closed then
        return nil, 'closed'
    end

    assert((type(pattern) == 'number' and pattern > 0)
        or pattern == '*l' or pattern == '*L', 'pattern must be a number great than 0 or "*l" or "*L"')

    local b = mt.b

    if type(pattern) == 'number' then
        return b:read(pattern, timeout)
    end

    return b:readline(timeout, pattern == '*l')
end

local function ssl_negotiate(mt, deadtime)
    local ssl, iow, ior = mt.ssl, mt.iow, mt.ior
    local ok, err, w

    while not ok do
        ok, err = ssl:negotiate()
        if err then
            return false, err
        end

        if ssl:state() == -2 then
            w = ior
        else
            w = iow
        end

        if not w:wait(deadtime - time.now()) then
            return nil, 'handshake timeout'
        end
    end

    return true
end

local function ssl_setmetatable(ctx, sock, methods, name)
    local ssock = {}

    if tonumber(_VERSION:match('%d%.%d')) < 5.2 then
        local __prox = newproxy(true)
        getmetatable(__prox).__gc = function() ssl_close(ssock) end
        ssock[__prox] = true
    end

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
        mt.ssl = ctx:new(fd, true)
        mt.iow = eco.watcher(eco.IO, fd, eco.WRITE)
        mt.b = buffer.new(function(b, timeout)
            if not mt.ior:wait(timeout) then
                return nil, 'timeout'
            end

            while true do
                local n, err = mt.ssl:read_buffer(b)
                if not n then
                    if err then
                        return nil, err
                    end

                    local state = mt.ssl:state()
                    local ok

                    if state == -2 then
                        ok = mt.ior:wait(timeout)
                    else
                        ok = mt.iow:wait(timeout)
                    end

                    if not ok then
                        return nil, 'timeout'
                    end
                else
                    if n == 0 then
                        return nil, 'closed'
                    end

                    return n
                end
            end
        end)
    end

    local ok, err = ssl_negotiate(mt, time.now() + 3.0)
    if not ok then
        return nil, err
    end

    return ssock
end

local server_methods = {
    close = ssl_close
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

    local ctx = ssl.context(true)

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

    local sock, err = listen(ipaddr, port)
    if not sock then
        return nil, err
    end

    return ssl_setmetatable(ctx, sock, server_methods, SSL_MT_SERVER)
end

function M.listen6(ipaddr, port, options)
    return M.listen(ipaddr, port, options, true)
end

function M.connect(ipaddr, port, ipv6)
    local connect = socket.connect_tcp

    if ipv6 then
        connect = socket.connect_tcp6
    end

    local sock, err = connect(ipaddr, port)
    if not sock then
        return nil, err
    end

    local ctx = ssl.context(false)

    return ssl_setmetatable(ctx, sock, client_methods, SSL_MT_CLIENT)
end

function M.connect6(ipaddr, port)
    return M.connect(ipaddr, port, true)
end

return M
