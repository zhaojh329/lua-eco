-- SPDX-License-Identifier: MIT
-- Author: Jianhui Zhao <zhaojh329@gmail.com>

local time = require 'eco.internal.time'
local file = require 'eco.internal.file'
local eco = require 'eco'

local M = {}

local timer_methods = {}

function timer_methods:cancel()
    self.rd:cancel()
end

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

function timer_methods:close()
    file.close(self.tfd)
end

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

-- The timer function is similar to `at`, but will not be started immediately.
function M.timer(cb, ...)
    assert(type(cb) == 'function')
    return creat_timer(time.CLOCK_MONOTONIC, cb, ...)
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
    assert(type(cb) == 'function')

    local tmr, err = M.timer(cb, ...)
    if not tmr then
        return nil, err
    end

    tmr:set(delay)

    return tmr
end

-- timer with absolute time
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

function M.sleep(delay)
    eco.sleep(delay)
end

return setmetatable(M, { __index = time })
