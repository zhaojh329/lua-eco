-- SPDX-License-Identifier: MIT
-- Author: Jianhui Zhao <zhaojh329@gmail.com>

local ubus = require 'eco.internal.ubus'
local eco = require 'eco'

local M = {}

local methods = {}

function methods:close()
    self.closed = true
    self.io:cancel()
    return self.con:close()
end

function methods:call(object, method, params, timeout)
    local co = coroutine.running()
    local con = self.con
    local datas = {}
    local status

    local req, err = con:call(object, method, params)
    if not req then
        return nil, err
    end

    self.handlers[req] = function(data)
        if type(data) == 'table' then
            datas[#datas + 1] = data
        else
            status = data
            eco.resume(co)
        end
    end

    if timeout and timeout > 0 then
        eco.sleep(timeout)
    else
        coroutine.yield()
    end

    if not status then
        con:abort_request(req)
        return nil, 'timeout'
    end

    if status ~= ubus.STATUS_OK then
        return nil, ubus.strerror(status)
    end

    return #datas == 0 and {} or table.unpack(datas)
end

function methods:send(event, params)
    return self.con:send(event, params)
end

function methods:reply(req, msg)
    return self.con:reply(req, msg)
end

function methods:listen(event, cb)
    local obj, err = self.con:listen(event)
    if not obj then
        return nil, err
    end

    self.handlers[obj] = cb

    return true
end

function methods:add(object, defs)
    local policies = {}

    for name, def in pairs(defs) do
        local cb, p = def[1], def[2]

        assert(type(cb) == 'function')
        assert(p == nil or type(p) == 'table')

        policies[name] = p or {}
    end

    local function handler(name, req, msg)
        eco.run(function()
            local cb = defs[name][1]
            local rc = cb(req, msg)
            if type(rc) ~= 'number' then rc = 0 end
            self.con:complete_deferred_request(req, rc)
        end)
    end

    local o, err = self.con:add(object, policies)
    if not o then
        return nil, err
    end

    self.handlers[o] = handler

    return o
end

function methods:subscribe(path, cb)
    local s, err = self.con:subscribe(path)
    if not s then
        return nil, err
    end

    self.handlers[s] = cb

    return true
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

local metatable = {
    __index = methods,
    __gc = methods.close,
    __close = methods.close
}

local function handle_event(ctx, auto_reconnect)
    local con = ctx.con

    while not ctx.closed do
        if not ctx.io:wait(eco.READ) then
            return
        end

        con:handle_event()

        if ctx.connection_lost then
            if not auto_reconnect then
                return
            end

            while true do
                local fd = con:reconnect()
                if fd then
                    ctx.io = eco.io(fd)
                    ctx.connection_lost = false
                    break
                end
                eco.sleep(3)
            end
        end
    end
end

function M.connect(path, auto_reconnect)
    local ctx = {
        connection_lost = false,
        handlers = {}
    }

    local cbs = {
        on_connection_lost = function() ctx.connection_lost = true end,

        on_data = function(obj, ...)
            local cb = ctx.handlers[obj]
            if not cb then
                return
            end

            cb(...)
        end
    }

    local con, err = ubus.connect(path, cbs)
    if not con then
        return nil, err
    end

    ctx.con = con
    ctx.io = eco.io(con:getfd())

    eco.run(handle_event, ctx, auto_reconnect)

    return setmetatable(ctx, metatable)
end

local function oneshot(name, ...)
    local con<close>, err = M.connect()
    if not con then
        return nil, err
    end

    return con[name](con, ...)
end

function M.call(object, method, params, timeout)
    return oneshot('call', object, method, params, timeout)
end

function M.send(event, params)
    return oneshot('send', event, params)
end

function M.objects()
    return oneshot('objects')
end

function M.signatures(object)
    return oneshot('signatures', object)
end

return setmetatable(M, { __index = ubus })
