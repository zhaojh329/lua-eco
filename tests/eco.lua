#!/usr/bin/env eco

local time = require 'eco.time'

for i = 1, 10000 do
    eco.run(function(n)
        while true do
            print(time.now(), 'eco', n, 'running')
            time.sleep(0.01)
        end
    end, i)
end
