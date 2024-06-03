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
    if cond:signal() then
        print('waked one coroutine')
    end
end)

-- wakes all coroutines waiting on the cond
time.at(3, function()
    local cnt = cond:broadcast()
    print('waked', cnt, 'coroutines')
end)
