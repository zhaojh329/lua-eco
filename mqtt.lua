-- SPDX-License-Identifier: MIT
-- Author: Jianhui Zhao <zhaojh329@gmail.com>

local mqtt  = require 'eco.core.mqtt'
local socket = require 'eco.socket'
local dns = require 'eco.dns'

local M = {}

local methods = {}

function methods:destroy()
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
    ok, err = __con:connect(address, port, keepalive)
    if not ok then
        return false, err
    end

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
    __index = methods
}

function M.new(id, clean_session)
    local con = mqtt.new(id, clean_session)

    return setmetatable({ con = con }, metatable)
end

return setmetatable(M, { __index = mqtt })
