#!/usr/bin/env eco

local time = require 'eco.time'

print('now:', time.now())

-- Set a timer to execute the callback function after 1.2 seconds
time.at(1.2, function(tmr, start)
    print(time.now() - start, 'seconds after')
end, time.now())

local tmr = time.at(3.0, function(tmr)
    print('I will be canceled')
end)

-- Cancel the timer
tmr:cancel()

time.at(1.0, function(tmr)
    print('again:', time.now())
    tmr:again()
end)
