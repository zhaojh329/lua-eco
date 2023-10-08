-- SPDX-License-Identifier: MIT
-- Author: Jianhui Zhao <zhaojh329@gmail.com>

local time = require 'eco.core.time'

local M = {}

local timers = {}
local timers_periodic = {}

local function new_timer(periodic)
    local tmrs = periodic and timers_periodic or timers
    for _, w in ipairs(tmrs) do
        if not w:active() then
            return w
        end
    end

    local w = eco.watcher(eco.TIMER, periodic)

    if #tmrs < 10 then
        tmrs[#tmrs + 1] = w
    end

    return w
end

-- returns the Unix time, the number of seconds elapsed since January 1, 1970 UTC.
function M.now()
    return time.now(eco.context())
end

--[[
    pauses the current coroutine for at least the delay seconds.
    A negative or zero delay causes sleep to return immediately.
--]]
function M.sleep(delay)
    local w = new_timer()
    return w:wait(delay)
end

local timer_methods = {}

function timer_methods:cancel()
    self.w:cancel()
end

function timer_methods:set(delay)
    local w = self.w

    w:cancel()

    eco.run(function(...)
        if w:wait(delay) then
            self.cb(...)
        end
    end, self, table.unpack(self.arguments))
end

local metatable = { __index = timer_methods }

-- The timer function is similar to `at`, but will not be started immediately.
function M.timer(cb, ...)
    assert(type(cb) == 'function')

    return setmetatable({
        w = new_timer(),
        cb = cb,
        arguments = { ... }
    }, metatable)
end

--[[
    The at function is used to create a timer that will execute a given callback function after
    a specified delay time.
    The callback function will receive the timer object as its first parameter, and the rest of
    the parameters will be the ones passed to the at function.

    The at function returns a timer object with two methods:
    set: Sets the timer to execute the callback function after the specified delay time.
    cancel: Cancels the timer so that the callback function will not be executed.
--]]
function M.at(delay, cb, ...)
    assert(type(delay) == 'number')

    local tmr = M.timer(cb, ...)

    tmr:set(delay)

    return tmr
end

function M.on(ts, cb, ...)
    assert(type(ts) == 'number')
    assert(type(cb) == 'function')

    local tmr = setmetatable({
        w = new_timer(true),
        cb = cb,
        arguments = { ... }
    }, metatable)

    tmr:set(ts)

    return tmr
end

return setmetatable(M, { __index = time })
