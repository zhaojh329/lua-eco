--[[
 * MIT License
 *
 * Copyright (c) 2022 Jianhui Zhao <zhaojh329@gmail.com>
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
--]]

local time = require 'eco.core.time'
local unpack = unpack or table.unpack

local M = {}

local timers = {}

local function new_timer()
    for _, w in ipairs(timers) do
        if not w:active() then
            return w
        end
    end

    local w = eco.watcher(eco.TIMER)

    if #timers < 10 then
        timers[#timers + 1] = w
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
    local mt = getmetatable(self)
    mt.w:cancel()
end

function timer_methods:set(delay)
    local mt = getmetatable(self)
    local w = mt.w

    w:cancel()

    eco.run(function(...)
        if w:wait(delay) then
            mt.cb(...)
        end
    end, self, unpack(mt.arguments))
end

--[[
    The at function is used to create a timer that will execute a given callback function after
    a specified delay time.
    The callback function will receive the timer object as its first parameter, and the rest of
    the parameters will be the ones passed to the at function.

    To use the at function, you need to provide three parameters:

    delay: Optional the amount of time to wait before executing the callback function, in seconds.
           If not provide this argument, you must call it's set method to start it.
    cb: The callback function that will be executed after the specified delay time.
    ...: Optional arguments to pass to the callback function.

    The at function returns a timer object with two methods:
    set: Sets the timer to execute the callback function after the specified delay time.
    cancel: Cancels the timer so that the callback function will not be executed.
--]]
function M.at(...)
    local arg1, arg2 = select(1, ...)
    local delay, cb, arguments

    if type(arg1) == 'number' then
        delay = arg1
        cb = arg2
        arguments = { select(3, ...) }
    else
        cb = arg1
        arguments = { select(2, ...) }
    end

    assert(type(cb) == 'function')

    local tmr = setmetatable({}, {
        w = new_timer(),
        cb = cb,
        arguments = arguments,
        __index = timer_methods
    })

    if delay then tmr:set(delay) end

    return tmr
end

return setmetatable(M, { __index = time })
