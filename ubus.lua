-- SPDX-License-Identifier: MIT
-- Author: Jianhui Zhao <zhaojh329@gmail.com>

local ubus = require 'eco.core.ubus'

local M = {}

local global_timeout = 30.0

local methods = {}

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

function methods:notify(object, params)
    return self.con:notify(object, params)
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
    __index = methods
}

function M.connect(path)
    local con, err = ubus.connect(path)

    if not con then
        return nil, err
    end

    con:settimeout(global_timeout)

    return setmetatable({
        con = con,
    }, metatable)
end

function M.call(object, method, params)
    local con, err = M.connect()
    if not con then
        return nil, err
    end

    local res, err = con:call(object, method, params)

    con:close()

    if res then
        return res
    end

    return nil, err
end

function M.send(event, params)
    local con, err = M.connect()
    if not con then
        return nil, err
    end

    local res, err = con:send(event, params)

    con:close()

    if res then
        return res
    end

    return nil, err
end

function M.objects()
    local con, err = M.connect()
    if not con then
        return nil, err
    end

    local res, err = con:objects()

    con:close()

    if res then
        return res
    end

    return nil, err
end

function M.signatures(object)
    local con, err = M.connect()
    if not con then
        return nil, err
    end

    local res, err = con:signatures(object)

    con:close()

    if res then
        return res
    end

    return nil, err
end

function M.settimeout(timeout)
    global_timeout = timeout
end

return setmetatable(M, { __index = ubus })
