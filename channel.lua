-- SPDX-License-Identifier: MIT
-- Author: Jianhui Zhao <zhaojh329@gmail.com>

local sync = require 'eco.sync'

--- Coroutine channel.
--
-- A channel provides a mechanism for communication between coroutines by
-- sending and receiving values.
--
-- - If the channel buffer is full, @{channel:send} blocks until a receiver
--   consumes an item (or `timeout` expires).
-- - If the channel buffer is empty, @{channel:recv} blocks until a sender
--   provides an item (or `timeout` expires).
-- - After @{channel:close}, receivers can still drain buffered items, but
--   sending will raise an error.
--
-- All timeouts are expressed in seconds.
--
-- @module eco.channel

local M = {}

--- Channel object returned by @{channel.new}.
-- @type channel
local methods = {}

--- Get the number of buffered items.
-- @function channel:length
-- @treturn int Number of buffered values.
function methods:length()
    return #self.buf
end

--- Close the channel.
--
-- This is idempotent.
--
-- After closing, @{channel:recv} returns `nil` once the buffer is drained.
-- @{channel:send} will raise an error.
--
-- @function channel:close
function methods:close()
    if self.closed then
        return
    end

    self.closed = true
    self.cond_recv:signal()
end

--- Send a value to the channel.
--
-- @function channel:send
-- @tparam any v Value to send.
-- @tparam[opt] number timeout Timeout in seconds.
-- @treturn boolean true On success.
-- @treturn[2] nil On timeout.
-- @treturn[2] string Error message (`'timeout'`).
-- @raise If the channel is closed.
function methods:send(v, timeout)
    assert(not self.closed, 'sending on closed channel')

    local buf = self.buf

    if #buf == self.capacity then
        local ok, err = self.cond_send:wait(timeout)
        if not ok then
            return nil, err
        end
    end

    buf[#buf + 1] = v

    self.cond_recv:signal()

    return true
end

--- Receive a value from the channel.
--
-- If the channel is closed and the buffer is empty, returns `nil`.
-- On timeout, returns `nil, 'timeout'`.
--
-- @function channel:recv
-- @tparam[opt] number timeout Timeout in seconds.
-- @treturn any v Received value.
-- @treturn[2] nil On closed (and buffer drained) or timeout.
-- @treturn[2] string Error message (`'timeout'`) on timeout.
function methods:recv(timeout)
    local buf = self.buf

    if #buf < 1 then
        if self.closed then
            return nil
        end

        local ok, err = self.cond_recv:wait(timeout)
        if not ok then
            return nil, err
        end
    end

    if #buf < 1  then
        return nil
    end

    local v = buf[1]

    table.remove(buf,  1)

    self.cond_send:signal()

    return v
end

--- End of `channel` class section.
-- @section end

local metatable = {
    __index = methods
}

--- Create a channel.
--
-- If `capacity` is not provided or is less than 1, it defaults to 1.
--
-- @function new
-- @tparam[opt=1] integer capacity Buffer capacity (number of values).
-- @treturn channel ch Channel instance.
-- @usage
-- local channel = require 'eco.channel'
-- local ch = channel.new(5)
-- ch:send('hello')
-- print(ch:recv())
function M.new(capacity)
    assert(capacity == nil or math.type(capacity) == 'integer', 'capacity must be an integer')

    if not capacity or capacity < 1 then
        capacity = 1
    end

    local ch = {
        cond_send = sync.cond(),
        cond_recv = sync.cond(),
        capacity = capacity,
        closed = false,
        buf = {}
    }

    return setmetatable(ch, metatable)
end

return M
