-- SPDX-License-Identifier: MIT
-- Author: Jianhui Zhao <zhaojh329@gmail.com>

local ubus = require 'eco.internal.ubus'
local eco = require 'eco'

local M = {}

local ms = {}

function ms:close()
    return self.con:close()
end

function ms:call(object, method, params, timeout)
    local co = coroutine.running()
    local con = self.con
    local datas = {}
    local status

    local req, err = con:call(object, method, params,
        function(data)
            datas[#datas + 1] = data
        end, function(ret)
            status = ret
            eco.resume(co)
        end)
    if not req then
        return nil, err
    end

    if timeout and timeout > 0 then
        eco.sleep(timeout)
    else
        coroutine.yield()
    end

    if not status then
        print(req)
        con:abort_request(req)
        return nil, 'timeout'
    end

    if status ~= ubus.STATUS_OK then
        return nil, ubus.strerror(status)
    end

    if #datas == 0 then
        return {}
    end

    return table.unpack(datas)
end

function ms:send(event, params)
    return self.con:send(event, params)
end

function ms:reply(req, msg)
    return self.con:reply(req, msg)
end

function ms:listen(event, cb)
    local obj, err = self.con:listen(event)
    if not obj then
        return nil, err
    end

    self.__objs[obj] = cb

    return true
end

function ms:add(object, methods)
    local policies = {}
    local cbs = {}

    for name, method in pairs(methods) do
        local cb, p = method[1], method[2]

        assert(type(cb) == 'function')
        assert(p == nil or type(p) == 'table')

        cbs[name] = cb
        policies[name] = p or {}
    end

    local function handler(name, req, msg)
        eco.run(function()
            local cb = cbs[name]
            local rc = cb(req, msg)
            if type(rc) ~= 'number' then rc = 0 end
            self.con:complete_deferred_request(req, rc)
        end)
    end

    local o, err = self.con:add(object, policies)
    if not o then
        return nil, err
    end

    self.__objs[o] = handler

    return o
end

function ms:subscribe(path, cb)
    local s, err = self.con:subscribe(path)
    if not s then
        return nil, err
    end

    self.__objs[s] = cb

    return true
end

function ms:notify(object, method, params)
    return self.con:notify(object, method, params)
end

function ms:objects()
    return self.con:objects()
end

function ms:signatures(object)
    return self.con:signatures(object)
end

local metatable = {
    __index = ms,
    __close = ms.close
}

local function handle_event(ctx, auto_reconnect)
    local con = ctx.con
    local io = eco.io(con:getfd())

    while true do
        io:wait(eco.READ)

        con:handle_event()

        if ctx.connection_lost then
            if not auto_reconnect then
                return
            end

            while true do
                local fd = con:reconnect()
                if fd then
                    io = eco.io(fd)
                end
                eco.sleep(3)
            end
        end
    end
end

function M.connect(path, auto_reconnect)
    local ctx = {
        connection_lost = false,
        __objs = {}
    }

    local cbs = {
        on_connection_lost = function() ctx.connection_lost = true end,

        on_data = function(obj, ...)
            local cb = ctx.__objs[obj]
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

    eco.run(handle_event, ctx, auto_reconnect)

    return setmetatable(ctx, metatable)
end

function M.call(object, method, params)
    local con<close>, err = M.connect()
    if not con then
        return nil, err
    end
    return con:call(object, method, params)
end

function M.send(event, params)
    local con<close>, err = M.connect()
    if not con then
        return nil, err
    end
    return con:send(event, params)
end

function M.objects()
    local con<close>, err = M.connect()
    if not con then
        return nil, err
    end
    return con:objects()
end

function M.signatures(object)
    local con<close>, err = M.connect()
    if not con then
        return nil, err
    end
    return con:signatures(object)
end

return setmetatable(M, { __index = ubus })
