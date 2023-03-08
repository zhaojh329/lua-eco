#!/usr/bin/env eco

local time = require 'eco.time'

print('now:', time.now())

-- Set a timer to execute the callback function after 0.5 seconds
time.at(0.5, function(tmr, start)
    print(time.now() - start, 'seconds after')
end, time.now()):start()

local tmr = time.at(3.0, function(tmr)
    print('I will be canceled')
end)

-- Start the timer
tmr:start()

-- Cancel the timer
tmr:cancel()

time.at(1.0, function(tmr)
    print('repeat:', time.now())
    tmr:start()
end):start()
