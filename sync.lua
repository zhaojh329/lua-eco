-- SPDX-License-Identifier: MIT
-- Author: Jianhui Zhao <zhaojh329@gmail.com>

local time = require 'eco.time'
local eco = require 'eco'

--- Coroutine synchronization primitives.
--
-- This module provides a small set of synchronization primitives designed for
-- `eco`'s cooperative coroutines (not OS threads):
--
-- - condition variables (`cond`)
-- - wait groups (`waitgroup`)
-- - mutual exclusion locks (`mutex`)
--
-- All timeouts are expressed in seconds.
--
-- @module eco.sync

local M = {}

--- Condition variable returned by @{sync.cond}.
--
-- A condition variable is a rendezvous point for coroutines waiting for, or
-- announcing, the occurrence of an event.
--
-- @type cond
local cond_methods = {}

--- Wait until signaled.
--
-- If signaled with a non-nil *truthy* `data`, returns that `data`.
-- Otherwise returns `true`.
--
-- @function cond:wait
-- @tparam[opt] number timeout Timeout in seconds.
-- @treturn any Data passed to @{cond:signal}, or `true`.
-- @treturn[2] nil On timeout.
-- @treturn[2] string Error message (`'timeout'`).
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

--- Wake one waiting coroutine.
--
-- If `data` is provided and is truthy, the waiter will receive `data` as the
-- return value of @{cond:wait}; otherwise it will receive `true`.
--
-- @function cond:signal
-- @tparam[opt] any data Data passed to the awakened waiter.
-- @treturn boolean `true` if a waiter was awakened.
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

--- Wake all waiting coroutines.
--
-- All awakened waiters will receive `true` as the return value of @{cond:wait}.
--
-- @function cond:broadcast
-- @treturn integer n Number of awakened coroutines.
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

--- End of `cond` class section.
-- @section end

local cond_mt = {
    __index = cond_methods
}

--- Create a condition variable.
--
-- @function cond
-- @treturn cond
function M.cond()
    return setmetatable({ waiters = {} }, cond_mt)
end

--- Wait group returned by @{sync.waitgroup}.
--
-- A wait group waits for a collection of coroutines to finish.
--
-- @type waitgroup
local waitgroup_methods = {}

--- Add delta to the wait group counter.
--
-- A positive `delta` increments the number of workers to wait for.
-- A negative `delta` decrements it.
--
-- @function waitgroup:add
-- @tparam integer delta
-- @raise If the counter would become negative.
function waitgroup_methods:add(delta)
   local counter = self.counter + delta
    if counter < 0 then
        error('negative waitgroup counter')
    end
    self.counter = counter
end

--- Decrement the wait group counter by one.
--
-- When the counter reaches zero, all waiters are awakened.
--
-- @function waitgroup:done
-- @raise If the counter would become negative.
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

--- Wait until the counter becomes zero.
--
-- @function waitgroup:wait
-- @tparam[opt] number timeout Timeout in seconds.
-- @treturn boolean true When the counter becomes zero.
-- @treturn[2] nil On timeout.
-- @treturn[2] string Error message (`'timeout'`).
function waitgroup_methods:wait(timeout)
    if self.counter == 0 then
        return true
    end

    return self.cond:wait(timeout)
end

--- End of `waitgroup` class section.
-- @section end

local waitgroup_mt = { __index = waitgroup_methods }

--- Create a wait group.
--
-- One coroutine calls @{waitgroup:add} to set the number of coroutines to wait
-- for. Then each of those coroutines runs and calls @{waitgroup:done} when
-- finished. Meanwhile, @{waitgroup:wait} can be used to block until all of
-- them have finished.
--
-- @function waitgroup
-- @treturn waitgroup
function M.waitgroup()
    return setmetatable({
        counter = 0,
        cond = M.cond()
    }, waitgroup_mt)
end

--- Mutex returned by @{sync.mutex}.
--
-- A mutex provides mutual exclusion between coroutines.
--
-- @type mutex
local mutex_methods = {}

--- Lock the mutex.
--
-- If the mutex is already locked, the current coroutine waits until it becomes
-- available or `timeout` expires.
--
-- @function mutex:lock
-- @tparam[opt] number timeout Timeout in seconds.
-- @treturn boolean true On success.
-- @treturn[2] nil On timeout.
-- @treturn[2] string Error message (`'timeout'`).
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

--- Unlock the mutex.
--
-- Wakes one coroutine waiting in @{mutex:lock}.
--
-- @function mutex:unlock
-- @raise If the mutex is not locked.
function mutex_methods:unlock()
    if not self.locked then
        error('unlock of unlocked mutex')
    end

    self.locked = false
    self.cond:signal()
end

--- End of `mutex` class section.
-- @section end

local mutex_mt = { __index = mutex_methods }

--- Create a mutex.
--
-- @function mutex
-- @treturn mutex
function M.mutex()
    return setmetatable({
        locked = false,
        cond = M.cond()
    }, mutex_mt)
end

return M
