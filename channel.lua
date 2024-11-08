-- SPDX-License-Identifier: MIT
-- Author: Jianhui Zhao <zhaojh329@gmail.com>

local sync = require 'eco.sync'

local M = {}

local methods = {}

function methods:length()
    return #self.buf
end

function methods:close()
    if self.closed then
        return
    end

    self.closed = true
    self.cond_recv:signal()
end

-- On success, true is returned
-- On error, false is returned with a string describing the error
function methods:send(v, timeout)
    assert(not self.closed, 'sending on closed channel')

    local buf = self.buf

    if #buf == self.capacity then
        local ok, err = self.cond_send:wait(timeout)
        if not ok then
            return false, err
        end
    end

    buf[#buf + 1] = v

    self.cond_recv:signal()

    return true
end

-- On success, the value received is returned
-- On closed, nil is returned
-- On error, nil is returned with a string describing the error
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

local metatable = {
    __index = methods
}

--[[
A channel provides a mechanism for communication between coroutines by sending and receiving values.

When a coroutine sends data to a channel, if the channel is full, the sending operation is blocked
until another coroutine has taken data from the channel.

Similarly, when a coroutine receives data from a channel, if there is no data available in the channel,
the receiving operation will be blocked until another coroutine has sent data to the channel.

Closing a channel notifies other coroutines that the channel is no longer in use. After a channel is closed,
other coroutines can still receive data from it, but they can no longer send data to it.

A channel can have a buffer, default is 1.
--]]
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
