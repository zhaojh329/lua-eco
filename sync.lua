-- SPDX-License-Identifier: MIT
-- Author: Jianhui Zhao <zhaojh329@gmail.com>

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

local sync = require 'eco.internal.sync'
local file = require 'eco.internal.file'
local time = require 'eco.time'
local eco = require 'eco'

local M = {}

--- Condition variable returned by @{sync.cond}.
--
-- A condition variable is a rendezvous point for coroutines waiting for, or
-- announcing, the occurrence of an event.
--
-- @type cond
local cond_methods = {}

-- Only one coroutine may own the eventfd read slot. Others stay pending until
-- the current reader finishes; handoff reserves the slot before resuming.
local function resume_pending_waiter(self)
    if self.closed then
        self.reading = nil

        for co, info in pairs(self.waiters) do
            if info.pending then
                info.pending = nil
                eco._resume(co)
            end
        end

        return
    end

    for co, info in pairs(self.waiters) do
        if info.pending then
            self.reading = co
            info.pending = nil
            eco._resume(co)
            return
        end
    end

    self.reading = nil
end

--- Wait until signaled.
--
-- If signaled with a non-nil *truthy* `data`, returns that `data`.
-- Otherwise returns `true`.
--
-- @function cond:wait
-- @tparam[opt] number timeout Timeout in seconds.
-- @treturn any Data passed to @{cond:signal}, or `true`.
-- @treturn[2] nil On timeout.
-- @treturn[2] string Error message (`'timeout'` or `'closed'`).
function cond_methods:wait(timeout)
    if self.closed then
        return nil, 'closed'
    end

    local waiters = self.waiters

    local co = coroutine.running()

    local info = {}
    local deadline

    waiters[co] = info

    if timeout then
        deadline = time.now() + timeout
    end

    while self.reading and self.reading ~= co do
        info.pending = true

        if self.closed then
            waiters[co] = nil
            return nil, 'closed'
        end

        if deadline and not info.signaled then
            local remaining = deadline - time.now()

            if remaining <= 0 then
                waiters[co] = nil
                return nil, 'timeout'
            end

            eco.sleep(remaining)

            if self.closed then
                waiters[co] = nil
                return nil, 'closed'
            end

            if info.pending and not info.signaled then
                waiters[co] = nil
                return nil, 'timeout'
            end
        else
            coroutine.yield()

            if self.closed then
                waiters[co] = nil
                return nil, 'closed'
            end
        end
    end

    info.pending = nil

    if self.closed then
        waiters[co] = nil
        return nil, 'closed'
    end

    self.reading = co

    local remaining = timeout

    if deadline and not info.signaled then
        remaining = deadline - time.now()

        if remaining <= 0 then
            waiters[co] = nil
            resume_pending_waiter(self)
            return nil, 'timeout'
        end
    end

    local ok, err = self.rd:read(8, remaining)

    -- A signal may race with an I/O timeout after the timeout has queued this
    -- coroutine but before it resumes. In that case, consume the signal and
    -- let it win; otherwise the eventfd credit would become stale.
    if not ok and info.signaled and not self.closed then
        ok, err = self.rd:read(8, 0)
    end

    waiters[co] = nil

    resume_pending_waiter(self)

    if self.closed then
        return nil, 'closed'
    end

    if not ok then
        return nil, err
    end

    return info.data or true
end

local function write_eventfd(self, n)
    self.wr:write(string.pack('I8', n))
    return true
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
    if self.closed then
        return false
    end

    local waiters = self.waiters
    local reading = self.reading

    if reading and waiters[reading] then
        local info = waiters[reading]

        info.data = data
        info.signaled = true

        return write_eventfd(self, 1)
    end

    for co in pairs(waiters) do
        local info = waiters[co]

        info.data = data
        info.signaled = true

        return write_eventfd(self, 1)
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
    if self.closed then
        return 0
    end

    local waiters = self.waiters
    local n = 0

    for co in pairs(waiters) do
        waiters[co].signaled = true
        n = n + 1
    end

    if n == 0 then
        return 0
    end

    write_eventfd(self, n)

    return n
end

--- Close the condition variable.
--
-- This is idempotent. Any coroutine blocked in @{cond:wait} is resumed and
-- receives `nil, 'closed'`.
function cond_methods:close()
    if self.closed then
        return
    end

    self.closed = true

    self.rd:cancel()
    self.wr:cancel()
    resume_pending_waiter(self)

    file.close(self.efd)
    self.efd = nil
end

--- End of `cond` class section.
-- @section end

local cond_mt = {
    __index = cond_methods,
    __gc = cond_methods.close,
    __close = cond_methods.close
}

--- Create a condition variable.
--
-- @function cond
-- @treturn cond
function M.cond()
    local efd, err = sync.eventfd(0, true)
    if not efd then
        return nil, err
    end

    return setmetatable({
        efd = efd,
        rd = eco.reader(efd),
        wr = eco.writer(efd),
        waiters = {},
        closed = false
    }, cond_mt)
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
    if not self.locked then
        self.locked = true
        return true
    end

    self.nwaiters = self.nwaiters + 1

    local ok, err = self.cond:wait(timeout)

    self.nwaiters = self.nwaiters - 1

    -- unlock() keeps the mutex locked while handing ownership to one waiter.
    return ok, err
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

    -- Keep the mutex locked until the selected waiter resumes. This prevents
    -- the unlocking coroutine or a newcomer from stealing the handoff.
    if self.nwaiters > 0 and self.cond:signal() then
        return
    end

    self.locked = false
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
        cond = M.cond(),
        nwaiters = 0
    }, mutex_mt)
end

return M
