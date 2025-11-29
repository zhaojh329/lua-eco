#!/usr/bin/env lua5.4

local time = require 'eco.time'
local eco = require 'eco'

eco.run(function()
    while true do
        eco.run(function() end)
        print(eco.count())
        time.sleep(0.01)
    end
end)

eco.loop()
