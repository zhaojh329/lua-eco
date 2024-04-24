#!/usr/bin/env eco

-- Using emqx for testing
-- docker run -d --name emqx -p 1883:1883 -p 8083:8083 -p 8084:8084 -p 8883:8883 -p 18083:18083 emqx/emqx:latest

local mqtt = require 'eco.mqtt'
local time = require 'eco.time'

local auto_reconnect = false

local function on_conack(ack, client)
    print('conack:', ack.rc, ack.reason, ack.session_present)

    if ack.rc ~= mqtt.CONNACK_ACCEPTED then
        return
    end

    client:subscribe('test', mqtt.QOS2)

    client:publish('eco', 'I am lua-eco MQTT', mqtt.QOS2)
end

local function on_suback(ack)
    if ack.rc == mqtt.SUBACK_FAILURE then
        print('suback:', ack.topic, 'fail')
    else
        print('suback:', ack.topic, ack.rc)
    end
end

local function on_unsuback(topic)
    print('unsuback:', topic)
end

local function on_publish(msg, client)
    print('message:', msg.topic, msg.payload)
    client:unsubscribe('test')
end

local function on_error(err)
    print('error:', err)
end

local client = mqtt.new({
    ipaddr = '127.0.0.1',
    clean_session = true
})

-- And you can set an option individually
client:set('keepalive', 5.0)

-- You can add multiple event handlers at once
client:on({
    conack = on_conack,
    suback = on_suback,
    unsuback = on_unsuback,
    publish = on_publish
})

-- Or add one event handler at a time
client:on('error', on_error)

while true do
    -- Start handling events until the network connection is closed
    client:run()

    if not auto_reconnect then
        break
    end

    print('reconnect in 5s...')

    time.sleep(5)
end
