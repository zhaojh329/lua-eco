-- SPDX-License-Identifier: MIT
-- Author: Jianhui Zhao <zhaojh329@gmail.com>

--- Time utilities.
--
-- This module provides a simple timer abstraction built on Linux `timerfd`,
-- integrated with lua-eco's coroutine scheduler.
--
-- @module eco.time

local time = require 'eco.internal.time'
local file = require 'eco.internal.file'
local eco = require 'eco'

local M = {
    --- Clock id for monotonic time.
    CLOCK_MONOTONIC = time.CLOCK_MONOTONIC,
    --- Clock id for realtime clock.
    CLOCK_REALTIME = time.CLOCK_REALTIME,
    --- `timerfd_settime()` flag: interpret `it_value` as an absolute time.
    TFD_TIMER_ABSTIME = time.TFD_TIMER_ABSTIME,
}

--- Timer object.
--
-- A timer instance is created by @{timer}, @{at}, or @{on}.
--
-- The callback signature is `cb(tmr, ...)`.
--
-- @type timer
local timer_methods = {}

--- Cancel the timer callback.
--
-- This cancels the pending read waiting for the timer to expire.
function timer_methods:cancel()
    self.rd:cancel()
end

--- Arm (or re-arm) the timer.
--
-- For timers created by @{timer} and @{at}, `delay` is a relative delay in
-- seconds.
--
-- For timers created by @{on}, `delay` is an absolute timestamp (seconds since
-- epoch), and will be passed to `timerfd_settime()` with `TFD_TIMER_ABSTIME`.
--
-- @tparam number delay Delay (relative or absolute, depending on timer type).
-- @treturn boolean ok
-- @treturn[opt] string err
function timer_methods:set(delay)
    local ok, err = time.timerfd_settime(self.tfd, self.flags, delay)
    if not ok then
        return nil, err
    end

    eco.run(function()
        if self.rd:read(8) then
            self.cb()
        end
    end)
end

--- Close the timer and release its file descriptor.
function timer_methods:close()
    file.close(self.tfd)
end

--- End of `timer` class section.
-- @section end

local metatable = {
    __index = timer_methods,
    __gc = timer_methods.close
}

local function creat_timer(clock_id, cb, ...)
    local tfd, err = time.timerfd_create(clock_id)
    if not tfd then
        return nil, err
    end

    local tmr = setmetatable({
        tfd = tfd,
        rd = eco.reader(tfd),
        flags = clock_id == time.CLOCK_REALTIME and time.TFD_TIMER_ABSTIME or 0
    }, metatable)

    local arguments = { ... }

    tmr.cb = function() cb(tmr, table.unpack(arguments)) end

    return tmr
end

--- Create a timer (not started).
--
-- The timer will not start until you call `timer:set`.
--
-- @tparam function cb Callback called as `cb(tmr, ...)`.
-- @tparam[opt] any ... Extra arguments passed to callback.
-- @treturn timer tmr
function M.timer(cb, ...)
    assert(type(cb) == 'function')
    return creat_timer(time.CLOCK_MONOTONIC, cb, ...)
end

--- Create and start a timer with a relative delay.
--
-- This is a convenience wrapper around `timer` + `timer:set`.
--
-- @tparam number delay Delay in seconds.
-- @tparam function cb Callback called as `cb(tmr, ...)`.
-- @tparam[opt] any ... Extra arguments passed to callback.
-- @treturn timer tmr
-- @treturn[opt] string err
function M.at(delay, cb, ...)
    assert(type(delay) == 'number')
    assert(type(cb) == 'function')

    local tmr, err = M.timer(cb, ...)
    if not tmr then
        return nil, err
    end

    tmr:set(delay)

    return tmr
end

--- Create and start a timer with an absolute timestamp.
--
-- @tparam number ts Absolute timestamp (seconds since epoch).
-- @tparam function cb Callback called as `cb(tmr, ...)`.
-- @tparam[opt] any ... Extra arguments passed to callback.
-- @treturn timer tmr
-- @treturn[opt] string err
function M.on(ts, cb, ...)
    assert(type(ts) == 'number')
    assert(type(cb) == 'function')

    local tmr, err = creat_timer(time.CLOCK_REALTIME, cb, ...)
    if not tmr then
        return nil, err
    end

    tmr:set(ts)

    return tmr
end

--- Alias of @{eco.sleep}.
--
-- @tparam number delay Sleep time in seconds.
function M.sleep(delay)
    eco.sleep(delay)
end

return setmetatable(M, { __index = time })
