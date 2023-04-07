-- SPDX-License-Identifier: MIT
-- Author: Jianhui Zhao <zhaojh329@gmail.com>

-- For more usage to see https://github.com/flukso/lua-mosquitto

local socket = require 'eco.socket'
local mosq  = require 'mosquitto'
local time = require 'eco.time'
local sys = require 'eco.sys'
local dns = require 'eco.dns'
local bit = require 'eco.bit'

local M = {}

local function mqtt_io_loop(mt)
    local done = mt.done
    local con = mt.con
    local w = mt.iow

    while not done.v do
        local ev = eco.READ

        if con:want_write() then
            ev = bit.bor(ev, eco.WRITE)
        end

        w:modify(ev)

        ev = w:wait()
        if not ev then
            break
        end

        if done.v then
            return
        end

        if bit.band(ev, eco.READ) > 0 then
            if not con:loop_read(1) then
                break
            end
        end

        if bit.band(ev, eco.WRITE) > 0 then
            if not con:loop_write(1) then
                break
            end
        end
    end

    done.v = true
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

    done.v = true
end

local methods = {}

function methods:destroy()
    local mt = getmetatable(self)
    mt.done.v = true

    if mt.ior then
        mt.ior:cancel()
    end

    if mt.iow then
        mt.iow:cancel()
    end

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

local function try_connect(mt, address, port, keepalive)
    local con = mt.con

    local s, err = socket.connect_tcp(address, port)
    if not s then
        return false, err
    end

    s:close()

    local ok
    ok, _, err = con:connect(address, port, keepalive)
    if not ok then
        return false, err
    end

    mt.iow = eco.watcher(eco.IO, con:socket(), eco.WRITE)
    mt.done.v = false

    eco.run(mqtt_io_loop, mt)
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

    local ok

    for _, a in ipairs(answers) do
        if a.type == dns.TYPE_A or a.type == dns.TYPE_AAAA then
            ok, err = try_connect(mt, a.address, port, keepalive)
            if ok then
                return true
            end
        end
    end

    return false, err
end

function M.new(id, clean_session)
    local con = mosq.new(id, clean_session)

    local o = {}

    if tonumber(_VERSION:match('%d%.%d')) < 5.2 then
        local __prox = newproxy(true)
        getmetatable(__prox).__gc = function() o:destroy() end
        o[__prox] = true
    end

    return setmetatable(o, {
        __index = methods,
        __gc = o.destroy,
        con = con,
        done = { v = true }
    })
end

return setmetatable(M, { __index = mosq })
