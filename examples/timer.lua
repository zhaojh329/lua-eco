#!/usr/bin/env eco

local time = require 'eco.time'

print('now', time.now())

-- Set a timer to execute the callback function after 0.5 seconds
time.at(0.5, function(tmr, start)
    print(time.now() - start, 'seconds after')
end, time.now())

local tmr0 = time.timer(function()
    print('I will be canceled')
end)

-- Start the timer
tmr0:set(3.0)

-- Cancel the timer
tmr0:cancel()

time.at(1.0, function(tmr)
    print('repeat:', time.now())
    tmr:set(1.0)
end)

-- timer with absolute time
time.on(time.now() + 1.5, function()
    print('absolute timer:', time.now())
end)
