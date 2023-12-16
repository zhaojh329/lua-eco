#!/usr/bin/env eco

local mqtt = require 'eco.mqtt'
local time = require 'eco.time'

local con = mqtt.new('eco-' .. os.time())

local disconnected = false

con:set_callback('ON_CONNECT', function(success, rc, str)
    print('ON_CONNECT:', success, rc, str)

    eco.run(function()
        local i = 0
        while not disconnected do
            print('pub', i)
            con:publish('eco', 'hello ' .. i)
            time.sleep(0.0001)
            i = i + 1
        end
    end)
end)

con:set_callback('ON_DISCONNECT', function(success, rc, str)
    print('ON_DISCONNECT:', success, rc, str)
    disconnected = true
end)

local ok, err = con:connect('localhost', 1883)
if not ok then
    error(err)
end

while true do
    time.sleep(1)
end
