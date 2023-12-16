#!/usr/bin/env eco

local mqtt = require 'eco.mqtt'
local time = require 'eco.time'

local con = mqtt.new('eco-' .. os.time())

con:set_callback('ON_CONNECT', function(success, rc, str)
    print('ON_CONNECT:', success, rc, str)

    con:subscribe('eco', 2)
end)

con:set_callback('ON_DISCONNECT', function(success, rc, str)
    print('ON_DISCONNECT:', success, rc, str)
end)

con:set_callback('ON_MESSAGE', function(mid, topic, payload, qos, retain)
    print('ON_MESSAGE:', mid, topic, payload, qos, retain)
end)

local ok, err = con:connect('localhost', 1883)
if not ok then
    error(err)
end

while true do
    time.sleep(1)
end
