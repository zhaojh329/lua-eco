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

-- https://github.com/flukso/lua-mosquitto

local socket = require 'eco.socket'
local mosq  = require 'mosquitto'
local time = require 'eco.time'
local sys = require 'eco.sys'
local dns = require 'eco.dns'

local M = {}

local function read_loop(mt)
    local done = mt.done
    local con = mt.con
    local w = mt.ior

    while not done.v do
        if not w:wait() then
            break
        end

        if not con:loop_read(10) then
            break
        end
    end
end

local function write_loop(mt)
    local done = mt.done
    local con = mt.con
    local w = mt.iow

    while not done.v do
        if not w:wait() then
            break
        end

        if con:want_write() then
            if not con:loop_write(10) then
                break
            end
        end

        time.sleep(0.1)
    end

    mt.ior:cancel()
end

local function check_keepalive_loop(mt)
    local done = mt.done
    local con = mt.con

    while not done.v do
        if not con:loop_misc() then
            break
        end
        time.sleep(1)
    end
end

local methods = {}

function methods:destroy()
    local mt = getmetatable(self)
    mt.done.v = true
    mt.ior:cancel()
    mt.iow:cancel()
    return mt.con:destroy()
end

function methods:disconnect()
    local mt = getmetatable(self)
    return mt.con:disconnect()
end

function methods:reinitialise(id, clean_session)
    local mt = getmetatable(self)
    return mt.con:reinitialise(id, clean_session)
end

function methods:will_set(topic, payload, qos, retain)
    local mt = getmetatable(self)
    return mt.con:will_set(topic, payload, qos, retain)
end

function methods:will_clear()
    local mt = getmetatable(self)
    return mt.con:will_clear()
end

function methods:login_set(username, password)
    local mt = getmetatable(self)
    return mt.con:login_set(username, password)
end

function methods:tls_insecure_set(insecure)
    local mt = getmetatable(self)
    return mt.con:tls_insecure_set(insecure)
end

function methods:tls_set(cafile, capath, certfile, keyfile)
    local mt = getmetatable(self)
    return mt.con:tls_set(cafile, capath, certfile, keyfile)
end

function methods:tls_psk_set(psk, identity, ciphers)
    local mt = getmetatable(self)
    return mt.con:tls_psk_set(psk, identity, ciphers)
end

function methods:tls_opts_set(cert_required, tls_version, ciphers)
    local mt = getmetatable(self)
    return mt.con:tls_psk_set(cert_required, tls_version, ciphers)
end

function methods:option(option, value)
    local mt = getmetatable(self)
    return mt.con:option(option, value)
end

function methods:publish(topic, payload, qos, retain)
    local mt = getmetatable(self)
    return mt.con:publish(topic, payload, qos, retain)
end

function methods:subscribe(topic, qos)
    local mt = getmetatable(self)
    return mt.con:subscribe(topic, qos)
end

function methods:unsubscribe(topic)
    local mt = getmetatable(self)
    return mt.con:unsubscribe(topic)
end

function methods:set_callback(typ, func)
    local mt = getmetatable(self)
    return mt.con:callback_set(typ, function(...)
        eco.run(func, ...)
    end)
end

local function wait_connected(mt, con)
    local fd = con:socket()
    local w = eco.watcher(eco.IO, fd, eco.WRITE)
    if not w:wait(3.0) then
        return false, 'timeout'
    end

    local err = socket.getoption(fd, 'error')
    if err ~= 0 then
        return false, sys.strerror(err)
    end

    mt.ior = eco.watcher(eco.IO, fd)
    mt.iow = w
    mt.done = { v = false }

    eco.run(read_loop, mt)
    eco.run(write_loop, mt)
    eco.run(check_keepalive_loop, mt)

    return true
end

function methods:connect(host, port, keepalive)
    local mt = getmetatable(self)
    local con = mt.con

    local answers, err = dns.query(host or 'localhost')
    if not answers then
        return false, err
    end

    local ok, err

    for _, a in ipairs(answers) do
        if a.type == dns.TYPE_A or a.type == dns.TYPE_AAAA then
            ok, _, err = con:connect_async(a.address, port, keepalive)
            if ok then
                ok, err = wait_connected(mt, con)
                if ok then
                    return true
                end
            end
        end
    end

    return false, err
end

function methods:reconnect()
    local mt = getmetatable(self)
    local con = mt.con

    local ok, _, err = con:reconnect_async()
    if not ok then
        return false, err
    end

    return wait_connected(mt, con)
end

function M.new(id, clean_session)
    local con = mosq.new(id, clean_session)

    return setmetatable({}, {
        __index = methods,
        con = con
    })
end

return setmetatable(M, { __index = mosq })
