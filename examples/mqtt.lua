#!/usr/bin/env eco

local mqtt = require 'eco.mqtt'

local con = mqtt.new('eco-' .. os.time())

local ok, err = con:connect('localhost', 1883)
if not ok then
    print('connect fail:', err)
    return
end

con:set_callback('ON_CONNECT', function(success, rc, str)
    print('ON_CONNECT:', success, rc, str)

    con:subscribe('$SYS/#')
    con:subscribe('eco', 2)

    con:publish("world", "hello")
end)

con:set_callback('ON_DISCONNECT', function(success, rc, str)
    print('ON_DISCONNECT:', success, rc, str)
end)

con:set_callback('ON_PUBLISH', function(mid)
    print('ON_PUBLISH:', mid)
end)

con:set_callback('ON_MESSAGE', function(mid, topic, payload, qos, retain)
    print('ON_MESSAGE:', mid, topic, payload, qos, retain)
end)

con:set_callback('ON_SUBSCRIBE', function(...)
    print('ON_SUBSCRIBE:', ...)
end)

con:set_callback('ON_UNSUBSCRIBE', function(mid)
    print('ON_UNSUBSCRIBE:', mid)
end)

con:set_callback('ON_LOG', function(level, str)
    print('ON_LOG:', level, str)
end)
