-- SPDX-License-Identifier: MIT
-- Author: Jianhui Zhao <zhaojh329@gmail.com>

local time = require 'eco.time'
local eco = require 'eco'

local M = {}

local cond_methods = {}

-- waiting to be awakened
function cond_methods:wait(timeout)
    local waiters = self.waiters

    local co = coroutine.running()

    waiters[co] = false

    if timeout and timeout > 0 then
        time.sleep(timeout)
        if not waiters[co] then
            waiters[co] = nil
            return nil, 'timeout'
        end
    else
        coroutine.yield()
    end

    local data = waiters[co]

    waiters[co] = nil

    return data
end

-- wakes one coroutine waiting on the cond, if there is any.
-- returns true if one coroutine was waked
function cond_methods:signal(data)
    local waiters = self.waiters

    for co in pairs(waiters) do
        if data ~= nil and data then
            waiters[co] = data
        else
            waiters[co] = true
        end

        eco.resume(co)
        return true
    end

    return false
end

-- wakes all coroutines waiting on the cond
-- returns the number of awakened coroutines
function cond_methods:broadcast()
    local waiters = self.waiters
    local n = 0

    for co in pairs(waiters) do
        waiters[co] = true
        eco.resume(co)
        n = n + 1
    end

    return n
end

local cond_mt = {
    __index = cond_methods
}

-- implements a condition variable, a rendezvous point for coroutines
-- waiting for or announcing the occurrence of an event.
function M.cond()
    return setmetatable({ waiters = {} }, cond_mt)
end

local waitgroup_methods = {}

function waitgroup_methods:add(delta)
   local counter = self.counter + delta
    if counter < 0 then
        error('negative waitgroup counter')
    end
    self.counter = counter
end

function waitgroup_methods:done()
    local counter = self.counter - 1

    if counter < 0 then
        error('negative wait group counter')
    end

    self.counter = counter

    if counter == 0 then
        self.cond:broadcast()
    end
end

function waitgroup_methods:wait(timeout)
    if self.counter == 0 then
        return true
    end

    return self.cond:wait(timeout)
end

local waitgroup_mt = { __index = waitgroup_methods }

--[[
    A waitgroup waits for a collection of coroutines to finish.
    One coroutine calls add to set the number of coroutines to wait for.
    Then each of the coroutines runs and calls done when finished.
    At the same time, wait can be used to block until all coroutines have finished.
--]]
function M.waitgroup()
    return setmetatable({
        counter = 0,
        cond = M.cond()
    }, waitgroup_mt)
end

local mutex_methods = {}

function mutex_methods:lock(timeout)
    while self.locked do
        local ok, err = self.cond:wait(timeout)
        if not ok then
            return nil, err
        end
    end

    self.locked = true
    return true
end

function mutex_methods:unlock()
    if not self.locked then
        error('unlock of unlocked mutex')
    end

    self.locked = false
    self.cond:signal()
end

local mutex_mt = { __index = mutex_methods }

function M.mutex()
    return setmetatable({
        locked = false,
        cond = M.cond()
    }, mutex_mt)
end

return M
