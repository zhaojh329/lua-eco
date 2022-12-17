#!/usr/bin/env eco

local time = require 'eco.time'

print('now:', time.now())

time.at(1.2, function(start)
    print(time.now() - start, 'seconds after')
end, time.now())

local tmr = time.at(3.0, function()
    print('I will be canceled')
end)

tmr:cancel()
