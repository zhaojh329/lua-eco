-- SPDX-License-Identifier: MIT
-- Author: Jianhui Zhao <zhaojh329@gmail.com>

local time = require 'eco.core.time'

local M = {}

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
        w = eco.watcher(eco.TIMER),
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
        w = eco.watcher(eco.TIMER, true),
        cb = cb,
        arguments = { ... }
    }, metatable)

    tmr:set(ts)

    return tmr
end

return setmetatable(M, { __index = time })
