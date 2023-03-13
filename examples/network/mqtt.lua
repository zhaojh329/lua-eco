#!/usr/bin/env eco

local mqtt = require 'eco.mqtt'
local time = require 'eco.time'
local log = require 'eco.log'

local auto_reconnect = true

local function reconnect(con)
    while true do
        local ok, err = con:connect('localhost', 1883)
        if ok then return end

        log.err('connect fail:', err)

        if not auto_reconnect then return end

        log.err('reconnect in 5s...')
        time.sleep(5)
    end
end

local con = mqtt.new('eco-' .. os.time())

con:set_callback('ON_CONNECT', function(success, rc, str)
    log.info('ON_CONNECT:', success, rc, str)

    con:subscribe('$SYS/#')
    con:subscribe('eco', 2)

    con:publish('world', 'hello')
end)

con:set_callback('ON_DISCONNECT', function(success, rc, str)
    log.info('ON_DISCONNECT:', success, rc, str)

    if auto_reconnect then
        time.sleep(5)
        reconnect(con)
    end
end)

con:set_callback('ON_PUBLISH', function(mid)
    log.info('ON_PUBLISH:', mid)
end)

con:set_callback('ON_MESSAGE', function(mid, topic, payload, qos, retain)
    log.info('ON_MESSAGE:', mid, topic, payload, qos, retain)
end)

con:set_callback('ON_SUBSCRIBE', function(...)
    log.info('ON_SUBSCRIBE:', ...)
end)

con:set_callback('ON_UNSUBSCRIBE', function(mid)
    log.info('ON_UNSUBSCRIBE:', mid)
end)

con:set_callback('ON_LOG', function(level, str)
    log.info('ON_LOG:', level, str)
end)

reconnect(con)

while true do
    time.sleep(1)
end
