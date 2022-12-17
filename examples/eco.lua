#!/usr/bin/env eco

local time = require 'eco.time'

eco.run(function(name)
    while true do
        print(time.now(), name, eco.id())
        time.sleep(1.0)
    end
end, 'eco1')

eco.run(function(name)
    while true do
        print(time.now(), name, eco.id())
        time.sleep(2.0)
    end
end, 'eco2')
