#!/usr/bin/env eco

local mqtt = require 'eco.mqtt'

local client = mqtt.new({ ipaddr = '127.0.0.1' })

client:on({
    conack = function(ack)
        print('conack:', ack.rc, ack.reason)

        if ack.rc ~= mqtt.CONNACK_ACCEPTED then
            return
        end

        client:subscribe('eco', mqtt.QOS2)
    end,

    publish = function(msg)
        print('message:', msg.payload:match('%d+'))
    end,

    error = function(err)
        print('error:', err)
    end
})

client:run()
