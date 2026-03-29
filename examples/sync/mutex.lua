#!/usr/bin/env eco

local time = require 'eco.time'
local sync = require 'eco.sync'
local eco = require 'eco'

local mutex = sync.mutex()

eco.run(function()
    mutex:lock()
    time.sleep(1)
    mutex:unlock()
end)

print(os.time(), 'lock...')
mutex:lock()
print(os.time(), 'locked')
mutex:unlock()
