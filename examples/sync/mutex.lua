#!/usr/bin/env eco

local time = require 'eco.time'
local sync = require 'eco.sync'

local mutex = sync.mutex()

eco.run(function()
    while true do
        mutex:lock()
        time.sleep(1)
        mutex:unlock()
    end
end)

eco.run(function()
    while true do
        mutex:lock()
        print(time.now())
        mutex:unlock()
    end
end)
