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

local M = {}

local cond_methods = {}

-- waiting to be awakened
function cond_methods:wait(timeout)
    local mt = getmetatable(self)
    local watchers = mt.watchers

    local w = eco.watcher(eco.ASYNC)

    watchers[#watchers + 1] = w

    return w:wait(timeout)
end

-- wakes one coroutine waiting on the cond, if there is any.
function cond_methods:signal()
    local mt = getmetatable(self)
    local watchers = mt.watchers

    if #watchers > 0 then
        watchers[1]:send()
        table.remove(watchers, 1)
    end
end

-- wakes all coroutines waiting on the cond
function cond_methods:broadcast()
    local mt = getmetatable(self)

    for _, w in ipairs(mt.watchers) do
        w:send()
    end

    mt.watchers = {}
end

-- implements a condition variable, a rendezvous point for coroutines waiting for or announcing the occurrence of an event.
function M.cond()
    return setmetatable({}, {
        watchers = {},
        __index = cond_methods
    })
end

local waitgroup_methods = {}

function waitgroup_methods:add(delta)
   local mt = getmetatable(self)
   mt.counter = mt.counter + delta
end

function waitgroup_methods:done()
    local mt = getmetatable(self)

    mt.counter = mt.counter - 1

    if mt.counter < 0 then
        error('negative wait group counter')
    end

    if mt.counter == 0 then
        mt.cond:broadcast()
    end
end

function waitgroup_methods:wait(timeout)
    local mt = getmetatable(self)

    if mt.counter == 0 then
        return true
    end

    return mt.cond:wait(timeout)
end

--[[
    A waitgroup waits for a collection of coroutines to finish.
    One coroutine calls add to set the number of coroutines to wait for.
    Then each of the coroutines runs and calls done when finished.
    At the same time, wait can be used to block until all coroutines have finished.
--]]
function M.waitgroup()
    return setmetatable({}, {
        counter = 0,
        cond = M.cond(),
        __index = waitgroup_methods
    })
end

return M
