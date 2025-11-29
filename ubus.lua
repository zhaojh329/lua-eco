-- SPDX-License-Identifier: MIT
-- Author: Jianhui Zhao <zhaojh329@gmail.com>

--- UBus support.
--
-- This module provides bindings to OpenWrt's ubus IPC system via libubus.
--
-- Note: connecting to ubus requires root privileges in this implementation.
--
-- @module eco.ubus

local ubus = require 'eco.internal.ubus'
local eco = require 'eco'

local M = {
    --- Return status: success.
    STATUS_OK = ubus.STATUS_OK,
    --- Return status: invalid command.
    STATUS_INVALID_COMMAND = ubus.STATUS_INVALID_COMMAND,
    --- Return status: invalid argument.
    STATUS_INVALID_ARGUMENT = ubus.STATUS_INVALID_ARGUMENT,
    --- Return status: method not found.
    STATUS_METHOD_NOT_FOUND = ubus.STATUS_METHOD_NOT_FOUND,
    --- Return status: object not found.
    STATUS_NOT_FOUND = ubus.STATUS_NOT_FOUND,
    --- Return status: no data.
    STATUS_NO_DATA = ubus.STATUS_NO_DATA,
    --- Return status: permission denied.
    STATUS_PERMISSION_DENIED = ubus.STATUS_PERMISSION_DENIED,
    --- Return status: timeout.
    STATUS_TIMEOUT = ubus.STATUS_TIMEOUT,
    --- Return status: not supported.
    STATUS_NOT_SUPPORTED = ubus.STATUS_NOT_SUPPORTED,
    --- Return status: unknown error.
    STATUS_UNKNOWN_ERROR = ubus.STATUS_UNKNOWN_ERROR,
    --- Return status: connection failed.
    STATUS_CONNECTION_FAILED = ubus.STATUS_CONNECTION_FAILED,

    --- Blob message policy type: array.
    ARRAY = ubus.ARRAY,
    --- Blob message policy type: table.
    TABLE = ubus.TABLE,
    --- Blob message policy type: string.
    STRING = ubus.STRING,
    --- Blob message policy type: int64.
    INT64 = ubus.INT64,
    --- Blob message policy type: int32.
    INT32 = ubus.INT32,
    --- Blob message policy type: int16.
    INT16 = ubus.INT16,
    --- Blob message policy type: int8.
    INT8 = ubus.INT8,
    --- Blob message policy type: double.
    DOUBLE = ubus.DOUBLE,
    --- Blob message policy type: boolean.
    BOOLEAN = ubus.BOOLEAN
}

local function oneshot(name, ...)
    local con<close>, err = M.connect()
    if not con then
        return nil, err
    end

    return con[name](con, ...)
end

--- Call a ubus method (one-shot connection).
--
-- This helper creates a temporary connection (via @{eco.ubus.connect}), performs
-- a call and closes the connection automatically.
--
-- @function call
-- @tparam string object UBus object path (e.g. `'network.interface.lan'`).
-- @tparam string method Method name.
-- @tparam[opt] table params Parameters table.
-- @tparam[opt] number timeout Timeout in seconds.
-- @treturn table Result table.
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
-- @usage
-- local ubus = require 'eco.ubus'
-- local res, err = ubus.call('eco', 'echo', { text = 'hello' }, 3)
-- if not res then
--     print('call failed:', err)
-- else
--     print(res.text)
-- end
function M.call(object, method, params, timeout)
    return oneshot('call', object, method, params, timeout)
end

--- Send an ubus event (one-shot connection).
--
-- This helper creates a temporary connection (via @{eco.ubus.connect}), sends the event
-- and closes the connection automatically.
--
-- @function send
-- @tparam string event Event name.
-- @tparam table params Event payload.
-- @treturn boolean true On success.
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
function M.send(event, params)
    return oneshot('send', event, params)
end

--- List ubus objects (one-shot connection).
--
-- @function objects
-- @treturn table objects A map of `id -> path`.
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
function M.objects()
    return oneshot('objects')
end

--- Get the signatures of an ubus object (one-shot connection).
--
-- @function signatures
-- @tparam string object UBus object path.
-- @treturn table signatures
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
function M.signatures(object)
    return oneshot('signatures', object)
end

--- UBus connection returned by @{ubus.connect}.
--
-- This object manages an ubus connection and dispatches events/call replies in
-- a background coroutine.
--
-- @type connection
local methods = {}

--- Close the connection.
--
-- @function connection:close
function methods:close()
    if self.closed then return end

    self.closed = true
    self.io:cancel()
    return self.ctx:close()
end

--- Call an ubus method using an existing connection.
--
-- @function connection:call
-- @tparam string object UBus object path.
-- @tparam string method Method name.
-- @tparam[opt] table params Parameters table.
-- @tparam[opt] number timeout Timeout in seconds.
-- @treturn table Result table.
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message (`'timeout'` or a libubus message).
function methods:call(object, method, params, timeout)
    if self.closed then return end

    local co = coroutine.running()
    local ctx = self.ctx
    local datas = {}
    local status

    local req, err = ctx:call(object, method, params)
    if not req then
        return nil, err
    end

    self.handlers[req] = function(_, data)
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
        ctx:abort_request(req)
        return nil, 'timeout'
    end

    if status ~= ubus.STATUS_OK then
        return nil, ubus.strerror(status)
    end

    return #datas == 0 and {} or table.unpack(datas)
end

--- Send an ubus event.
--
-- @function connection:send
-- @tparam string event Event name.
-- @tparam table params Event payload.
-- @treturn boolean true On success.
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
function methods:send(event, params)
    if self.closed then return end
    return self.ctx:send(event, params)
end

--- Reply to a request.
--
-- This is called from handlers registered via @{connection:add}.
--
-- @function connection:reply
-- @tparam lightuserdata req Request handle.
-- @tparam table msg Reply message.
-- @treturn boolean true On success.
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
function methods:reply(req, msg)
    if self.closed then return end
    return self.ctx:reply(req, msg)
end

--- Listen to ubus events.
--
-- The callback will be called as `cb(con, event, msg)`.
--
-- @function connection:listen
-- @tparam string event Event name, or `'*'` for all.
-- @tparam function cb Callback `cb(con, event, msg)`.
-- @treturn boolean true On success.
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
function methods:listen(event, cb)
    if self.closed then return end

    local obj, err = self.ctx:listen(event)
    if not obj then
        return nil, err
    end

    self.handlers[obj] = cb

    return true
end

--- Add a ubus object with method handlers.
--
-- `defs` is a table mapping method name to `{ cb, policy }`.
--
-- The method callback is executed in a new coroutine as:
--
-- `cb(con, req, msg)`
--
-- You usually send the reply using @{connection:reply}.
-- The callback may return a numeric ubus status code; non-number return values
-- are treated as `0`.
--
-- `policy` is a table mapping field name to policy type (e.g. `ubus.STRING`,
-- `ubus.INT32`).
--
-- @function connection:add
-- @tparam string object Object name.
-- @tparam table defs Method definition table.
-- @treturn lightuserdata obj Object handle (opaque).
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
-- @usage
-- local ubus = require 'eco.ubus'
-- local con = assert(ubus.connect())
--
-- local defs = {
--     echo = {
--         function(con, req, msg)
--             con:reply(req, msg)
--         end,
--         { text = ubus.STRING }
--     }
-- }
--
-- con:add('eco', defs)
function methods:add(object, defs)
    if self.closed then return end

    local policies = {}

    for name, def in pairs(defs) do
        local cb, p = def[1], def[2]

        assert(type(cb) == 'function')
        assert(p == nil or type(p) == 'table')

        policies[name] = p or {}
    end

    local function handler(con, name, req, msg)
        eco.run(function()
            local cb = defs[name][1]
            local rc = cb(con, req, msg)
            if type(rc) ~= 'number' then rc = 0 end
            self.ctx:complete_deferred_request(req, rc)
        end)
    end

    local o, err = self.ctx:add(object, policies)
    if not o then
        return nil, err
    end

    self.handlers[o] = handler

    return o
end

--- Subscribe to notifications of an ubus object.
--
-- The callback will be called as `cb(con, method, msg)`.
--
-- @function connection:subscribe
-- @tparam string path Object path.
-- @tparam function cb Callback `cb(con, method, msg)`.
-- @treturn boolean true On success.
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
function methods:subscribe(path, cb)
    if self.closed then return end

    local s, err = self.ctx:subscribe(path)
    if not s then
        return nil, err
    end

    self.handlers[s] = cb

    return true
end

--- Send a notification from an object.
--
-- @function connection:notify
-- @tparam lightuserdata object Object handle returned by @{connection:add}.
-- @tparam string method Notification method name.
-- @tparam table params Payload.
-- @treturn boolean true On success.
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
function methods:notify(object, method, params)
    if self.closed then return end
    return self.ctx:notify(object, method, params)
end

--- List ubus objects.
--
-- @function connection:objects
-- @treturn table objects A map of `id -> path`.
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
function methods:objects()
    if self.closed then return end
    return self.ctx:objects()
end

--- Get the signatures of an ubus object.
--
-- @function connection:signatures
-- @tparam string object UBus object path.
-- @treturn table signatures
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
function methods:signatures(object)
    if self.closed then return end
    return self.ctx:signatures(object)
end

--- End of `connection` class section.
-- @section end

local metatable = {
    __index = methods,
    __gc = methods.close,
    __close = methods.close
}

local function handle_event(con, auto_reconnect)
    local ctx = con.ctx

    while not con.closed do
        if not con.io:wait(eco.READ) then
            return
        end

        ctx:handle_event()

        if con.connection_lost then
            if not auto_reconnect then
                return
            end

            while true do
                local fd = ctx:reconnect()
                if fd then
                    con.io = eco.io(fd)
                    con.connection_lost = false
                    break
                end
                eco.sleep(3)
            end
        end
    end
end

local connections = setmetatable({}, { __mode = 'v' })

local handlers = {
    on_connection_lost = function(ctx)
        connections[ctx].connection_lost = true
    end,

    on_data = function(ctx, obj, ...)
        local con = connections[ctx]
        local cb = con.handlers[obj]
        if not cb then
            return
        end

        cb(con, ...)
    end
}

--- Connect to ubus.
--
-- This creates a connection object and starts a background coroutine to
-- dispatch events and call replies.
--
-- Note: this implementation requires root privileges.
--
-- @function connect
-- @tparam[opt] string path UBus socket path.
-- @tparam[opt=false] boolean auto_reconnect Automatically reconnect when connection is lost.
-- @treturn connection
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
function M.connect(path, auto_reconnect)
    local con = {
        connection_lost = false,
        handlers = {}
    }

    local ctx, err = ubus.connect(path, handlers)
    if not ctx then
        return nil, err
    end

    connections[ctx] = con

    con.ctx = ctx
    con.io = eco.io(ctx:getfd())

    eco.run(handle_event, con, auto_reconnect)

    return setmetatable(con, metatable)
end

return setmetatable(M, { __index = ubus })
