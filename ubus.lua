-- SPDX-License-Identifier: MIT
-- Author: Jianhui Zhao <zhaojh329@gmail.com>

local ubus = require 'eco.core.ubus'

local M = {}

local call_timeout = 30.0

local function process_msg(con, w, done)
    while not done.v do
        if not w:wait() then
            return
        end
        con:handle_event()
    end
end

local methods = {}

function methods:closed()
    return self.done.v
end

function methods:close()
    local done = self.done
    local con = self.con

    if done.v then
        return
    end

    done.v = true
    self.w:cancel()
    con:close()
end

function methods:call(object, method, params)
    if self.done.v then
        return nil, 'closed'
    end

    local w = eco.watcher(eco.ASYNC)

    local msgs = {}
    local req, err

    req, err = self.con:call(object, method, params,
        function(msg)
            msgs[#msgs + 1] = msg
        end,
        function(ret)
            if ret ~= ubus.STATUS_OK then
                err = ubus.strerror(ret)
            end
            w:send()
        end
    )
    if not req then
        return nil, err
    end

    local ok = w:wait(call_timeout)
    if not ok then
        req:abort()
        return nil, 'timeout'
    end

    req:close()

    if err then
        return nil, err
    end

    if #msgs == 1 then
        return msgs[1]
    elseif #msgs > 1 then
        return msgs
    else
        return {}
    end
end

function methods:reply(req, msg)
    if self.done.v then
        return nil, 'closed'
    end

    return self.con:reply(req, msg)
end

function methods:add(object, methods)
    local con = self.con

    if self.done.v then
        return nil, 'closed'
    end

    for _, m in pairs(methods) do
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

    local o, err = con:add(object, methods)
    if not o then
        return false, err
    end

    return true
end

function methods:listen(event, cb)
    if self.done.v then
        return nil, 'closed'
    end

    local e, err = self.con:listen(event, function(...)
        eco.run(cb, ...)
    end)
    if not e then
        return false, err
    end

    return true
end

function methods:send(event, msg)
    if self.done.v then
        return nil, 'closed'
    end

    return self.con:send(event, msg)
end

function methods:objects()
    if self.done.v then
        return nil, 'closed'
    end

    return self.con:objects()
end

local metatable = {
    __index = methods,
    __gc = methods.close
}

function M.connect(path)
    local __con, err = ubus.connect(eco.context(), path)

    if not __con then
        return nil, err
    end

    local w = eco.watcher(eco.IO, __con:getfd())
    local done = { v = false }

    eco.run(process_msg, __con, w, done)

    return setmetatable({
        w = w,
        done = done,
        con = __con,
    }, metatable)
end

function M.call(object, method, params)
    local con, err = M.connect()
    if not con then
        return nil, err
    end

    local res, err = con:call(object, method, params)
    con:close()
    return res, err
end

function M.send(event, params)
    local con, err = ubus.connect(eco.context())
    if not con then
        return nil, err
    end

    con:send(event, params)
    con:close()

    return true
end

function M.objects()
    local con, err = ubus.connect(eco.context())
    if not con then
        return nil, err
    end

    local objects, err = con:objects()
    con:close()

    if objects then
        return objects
    end

    return nil, err
end

function M.settimeout(timeout)
    call_timeout = timeout
end

return setmetatable(M, { __index = ubus })
