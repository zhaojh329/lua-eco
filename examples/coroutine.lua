#!/usr/bin/env eco

local time = require 'eco.time'
local eco = require 'eco'

eco.run(function(name)
    local co = coroutine.running()
    while true do
        print(time.now(), name, co)
        time.sleep(1.0)
    end
end, 'eco1')

eco.run(function(name)
    local co = coroutine.running()
    while true do
        print(time.now(), name, co)
        time.sleep(2.0)
    end
end, 'eco2')

local co = coroutine.running()
while true do
    print(time.now(), 'eco0', co)
    time.sleep(3.0)
end
