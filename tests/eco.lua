#!/usr/bin/env eco

local time = require 'eco.time'

for i = 1, 10000 do
    eco.run(function(i)
        while true do
            print(time.now(), 'eco', i, 'running')
            time.sleep(0.01)
        end
    end, i)
end
