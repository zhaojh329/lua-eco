#!/usr/bin/env lua5.4

local ubus = require 'eco.ubus'
local time = require 'eco.time'
local eco = require 'eco'

eco.run(function()
    local con, err = ubus.connect()
    if not con then
        error(err)
    end

    local obj = con:add('eco', {})

    while true do
        time.sleep(1)
        local ts = time.now()
        print('notify...', ts)
        con:notify(obj, 'time', { ts = ts })
    end
end)

eco.run(function()
    local con, err = ubus.connect()
    if not con then
        error(err)
    end

    con:subscribe('eco', function(method, msg)
        if method == 'time' then
            print('recv:', msg.ts)
        end
    end)

    while true do
        time.sleep(1000)
    end
end)

eco.loop()
