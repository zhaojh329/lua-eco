#!/usr/bin/env eco

local time = require 'eco.time'

while true do
    eco.run(function() end)
    print(eco.count())
    time.sleep(0.01)
end
