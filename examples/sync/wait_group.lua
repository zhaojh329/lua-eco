#!/usr/bin/env eco

local sync = require 'eco.sync'

local wg = sync.waitgroup()

wg:add(10)

for i = 1, 10 do
    eco.run(function()
        print(i)
        wg:done()
    end, i)
end

wg:wait()
