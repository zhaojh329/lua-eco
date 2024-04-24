#!/usr/bin/env eco

local mqtt = require 'eco.mqtt'
local time = require 'eco.time'

local client = mqtt.new({ ipaddr = '127.0.0.1' })

local function publish_loop()
    local data = {}

    -- build 1MB data
    for _ = 1, 1024 * 1024 do
        data[#data + 1] = 'x'
    end

    data = table.concat(data)

    local i = 0

    while true do
        local n = string.format('%010d', i)

        print('pub', n)

        local ok, err = client:publish('eco', n .. data, mqtt.QOS2)
        if not ok then
            print('publish:', err)
            break
        end

        time.sleep(0.001)

        i = i + 1
    end
end

client:on({
    conack = function(ack)
        print('conack:', ack.rc, ack.reason)

        if ack.rc ~= mqtt.CONNACK_ACCEPTED then
            return
        end

        eco.run(publish_loop)
    end,

    error = function(err)
        print('error:', err)
    end
})

client:run()
