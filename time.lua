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

--[[
    waits for the delay seconds to elapse and then calls cb with any arguments you passed in its own coroutine.
    It returns a TIMER watcher that can be used to cancel the call using its cancel method.
--]]
function M.at(delay, cb, ...)
    local w = new_timer()

    eco.run(function(...)
        if w:wait(delay) then
            cb(...)
        end
    end, ...)

    return w
end

return setmetatable(M, { __index = time })
