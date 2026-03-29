#!/usr/bin/env eco

local ubus = require 'eco.ubus'
local time = require 'eco.time'

local function notify()
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
end

local function subscribe()
    local con, err = ubus.connect()
    if not con then
        error(err)
    end

    local sub = con:subscribe('eco', function(method, msg)
        if method == 'time' then
            print('recv:', msg.ts)
        end
    end, true)

    time.at(3, function()
        con:unsubscribe(sub)
        print('unsubscribed')
    end)
end

subscribe()
notify()
