#!/usr/bin/env lua5.4

local time = require 'eco.time'
local eco = require 'eco'

eco.run(function(name)
    while true do
        print(time.now(), name, coroutine.running())
        time.sleep(1.0)
    end
end, 'eco1')

eco.run(function(name)
    while true do
        print(time.now(), name, coroutine.running())
        time.sleep(2.0)
    end
end, 'eco2')

eco.loop()
