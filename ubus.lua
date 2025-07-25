-- SPDX-License-Identifier: MIT
-- Author: Jianhui Zhao <zhaojh329@gmail.com>

local ubus = require 'eco.core.ubus'

local M = {}

local methods = {}

local global_conn

function methods:close()
    return self.con:close()
end

function methods:call(object, method, params)
    return self.con:call(object, method, params)
end

function methods:reply(req, params)
    return self.con:reply(req, params)
end

function methods:send(event, params)
    return self.con:send(event, params)
end

function methods:notify(object, method, params)
    return self.con:notify(object, method, params)
end

function methods:objects()
    return self.con:objects()
end

function methods:signatures(object)
    return self.con:signatures(object)
end

function methods:settimeout(timeout)
    return self.con:settimeout(timeout)
end

function methods:auto_reconnect()
    return self.con:auto_reconnect()
end

function methods:add(object, ms)
    local con = self.con

    for _, m in pairs(ms) do
        local cb = m[1]

        assert(type(cb) == 'function')

        m[1] = function(req, msg)
            eco.run(function()
                local rc = cb(req, msg)
                if type(rc) ~= 'number' then rc = 0 end
                con:complete_deferred_request(req, rc)
            end)
        end
    end

    return con:add(object, ms)
end

function methods:subscribe(path, cb)
    local s, err = self.con:subscribe(path, function(...)
        eco.run(cb, ...)
    end)
    if not s then
        return false, err
    end

    return true
end

function methods:listen(event, cb)
    local e, err = self.con:listen(event, function(...)
        eco.run(cb, ...)
    end)
    if not e then
        return false, err
    end

    return true
end

local metatable = {
    __index = methods,
    __close = methods.close
}

function M.connect(path)
    local con, err = ubus.connect(path)

    if not con then
        return nil, err
    end

    return setmetatable({
        con = con,
    }, metatable)
end

function M.call(object, method, params)
    return global_conn:call(object, method, params)
end

function M.send(event, params)
    return global_conn:send(event, params)
end

function M.objects()
    return global_conn:objects()
end

function M.signatures(object)
    return global_conn:signatures(object)
end

global_conn = ubus.connect()

return setmetatable(M, { __index = ubus })
