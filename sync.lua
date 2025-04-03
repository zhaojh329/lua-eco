-- SPDX-License-Identifier: MIT
-- Author: Jianhui Zhao <zhaojh329@gmail.com>

local M = {}

local cond_methods = {}

-- waiting to be awakened
function cond_methods:wait(timeout)
    local watchers = self.watchers

    local w = eco.watcher(eco.ASYNC)

    watchers[#watchers + 1] = w

    return w:wait(timeout)
end

-- wakes one coroutine waiting on the cond, if there is any.
-- returns true if one coroutine was waked
function cond_methods:signal()
    local watchers = self.watchers

    if #watchers > 0 then
        watchers[1]:send()
        table.remove(watchers, 1)
        return true
    end

    return false
end

-- wakes all coroutines waiting on the cond
-- returns the number of awakened coroutines
function cond_methods:broadcast()
    local cnt = #self.watchers

    for _, w in ipairs(self.watchers) do
        w:send()
    end

    self.watchers = {}

    return cnt
end

local cond_mt = { __index = cond_methods }

-- implements a condition variable, a rendezvous point for coroutines waiting for or announcing the occurrence of an event.
function M.cond()
    return setmetatable({ watchers = {} }, cond_mt)
end

local waitgroup_methods = {}

function waitgroup_methods:add(delta)
   self.counter = self.counter + delta
end

function waitgroup_methods:done()
    local counter = self.counter

    counter = counter - 1

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

function mutex_methods:lock()
    self.counter = self.counter + 1

    if self.counter == 1 then
        return
    end

    self.cond:wait()
end

function mutex_methods:unlock()
    self.counter = self.counter - 1

    if self.counter == 0 then
        return
    end

    self.cond:signal()
end

local mutex_mt = { __index = mutex_methods }

function M.mutex()
    return setmetatable({
        counter = 0,
        cond = M.cond()
    }, mutex_mt)
end

return M
