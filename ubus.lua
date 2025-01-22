-- SPDX-License-Identifier: MIT
-- Author: Jianhui Zhao <zhaojh329@gmail.com>

local ubus = require 'eco.core.ubus'

local M = {}

local global_timeout = 30.0

local methods = {}

for _, method in ipairs({'close', 'call', 'reply', 'send', 'notify', 'objects', 'signatures', 'settimeout', 'auto_reconnect'}) do
    methods[method] = function(self, ...)
        local con = self.con
        return con[method](con, ...)
    end
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

for _, method in ipairs({'call', 'send', 'objects', 'signatures'}) do
    M[method] = function(...)
        local con, err = M.connect()
        if not con then
            return nil, err
        end

        local res, err = con[method](con, ...)

        con:close()

        if res then
            return res
        end

        return nil, err
    end
end

function M.settimeout(timeout)
    global_timeout = timeout
end

return setmetatable(M, { __index = ubus })
