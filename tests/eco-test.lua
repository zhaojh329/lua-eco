#!/usr/bin/env lua5.4

local time = require 'eco.time'
local eco = require 'eco'

for i = 1, 10000 do
    eco.run(function(n)
        while true do
            print(time.now(), 'eco', n, 'running')
            time.sleep(0.01)
        end
    end, i)
end

eco.loop()
