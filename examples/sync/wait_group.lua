#!/usr/bin/env lua5.4

local sync = require 'eco.sync'
local eco = require 'eco'

local wg = sync.waitgroup()

wg:add(10)

eco.run(function()
    for i = 1, 10 do
        eco.run(function()
            print(i)
            wg:done()
        end, i)
    end

    wg:wait()
end)

eco.loop()
