-- SPDX-License-Identifier: MIT
-- Author: Jianhui Zhao <zhaojh329@gmail.com>

local mqtt  = require 'eco.core.mqtt'
local socket = require 'eco.socket'
local time = require 'eco.time'
local dns = require 'eco.dns'

local M = {}

local function mqtt_io_loop(con)
    local done = con.done
    local __con = con.con
    local w = con.iow

    while not done.v do
        local ev = eco.READ

        if __con:want_write() then
            ev = ev | eco.WRITE
        end

        w:modify(ev)

        ev = w:wait()
        if not ev then
            break
        end

        if done.v then
            return
        end

        if ev & eco.READ > 0 then
            if not __con:loop_read(1) then
                break
            end
        end

        if ev & eco.WRITE > 0 then
            if not __con:loop_write(1) then
                break
            end
        end
    end

    done.v = true
end

local function check_keepalive_loop(con)
    local done = con.done
    local __con = con.con

    while not done.v do
        if not __con:loop_misc() then
            break
        end
        time.sleep(1)
    end

    done.v = true
end

local methods = {}

function methods:destroy()
    self.done.v = true

    if self.ior then
        self.ior:cancel()
    end

    if self.iow then
        self.iow:cancel()
    end

    return self.con:destroy()
end

function methods:disconnect()
    return self.con:disconnect()
end

function methods:reinitialise(id, clean_session)
    return self.con:reinitialise(id, clean_session)
end

function methods:will_set(topic, payload, qos, retain)
    return self.con:will_set(topic, payload, qos, retain)
end

function methods:will_clear()
    return self.con:will_clear()
end

function methods:login_set(username, password)
    return self.con:login_set(username, password)
end

function methods:tls_insecure_set(insecure)
    return self.con:tls_insecure_set(insecure)
end

function methods:tls_set(cafile, capath, certfile, keyfile)
    return self.con:tls_set(cafile, capath, certfile, keyfile)
end

function methods:tls_psk_set(psk, identity, ciphers)
    return self.con:tls_psk_set(psk, identity, ciphers)
end

function methods:tls_opts_set(cert_required, tls_version, ciphers)
    return self.con:tls_psk_set(cert_required, tls_version, ciphers)
end

function methods:option(option, value)
    return self.con:option(option, value)
end

function methods:publish(topic, payload, qos, retain)
    return self.con:publish(topic, payload, qos, retain)
end

function methods:subscribe(topic, qos)
    return self.con:subscribe(topic, qos)
end

function methods:unsubscribe(topic)
    return self.con:unsubscribe(topic)
end

function methods:set_callback(typ, func)
    return self.con:callback_set(typ, function(...)
        eco.run(func, ...)
    end)
end

local function try_connect(con, address, port, keepalive)
    local __con = con.con

    local s, err = socket.connect_tcp(address, port)
    if not s then
        return false, err
    end

    s:close()

    local ok
    ok, _, err = __con:connect(address, port, keepalive)
    if not ok then
        return false, err
    end

    con.iow = eco.watcher(eco.IO, __con:socket(), eco.WRITE)
    con.done.v = false

    eco.run(mqtt_io_loop, con)
    eco.run(check_keepalive_loop, con)

    return true
end

function methods:connect(host, port, keepalive)
    local answers, err = dns.query(host or 'localhost')
    if not answers then
        return false, err
    end

    local ok

    for _, a in ipairs(answers) do
        if a.type == dns.TYPE_A or a.type == dns.TYPE_AAAA then
            ok, err = try_connect(self, a.address, port, keepalive)
            if ok then
                return true
            end
        end
    end

    return false, err
end

local metatable = {
    __index = methods,
    __gc = methods.destroy
}

function M.new(id, clean_session)
    local con = mqtt.new(eco.context(), id, clean_session)

    return setmetatable({
        con = con,
        done = { v = true }
    }, metatable)
end

return setmetatable(M, { __index = mqtt })
