#!/usr/bin/env eco

local time = require 'eco.time'
local sync = require 'eco.sync'

local cond = sync.cond()

for i = 1, 4 do
    eco.run(function()
        print('eco-' .. i, 'waiting to be awakened...')
        cond:wait()
        print('eco-' .. i, 'awakened at', time.now())
    end, i)
end

-- wakes one coroutine waiting on the cond
time.at(1, function()
    cond:signal()
end)

-- wakes all coroutines waiting on the cond
time.at(3, function()
    cond:broadcast()
end)
