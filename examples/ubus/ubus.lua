#!/usr/bin/env lua5.4

local ubus = require 'eco.ubus'
local time = require 'eco.time'
local sys = require 'eco.sys'
local eco = require 'eco'

sys.signal(sys.SIGINT, function()
    print('\nGot SIGINT, now quit')
    eco.unloop()
end)

local con, err = ubus.connect()
if not con then
    error(err)
end

con:listen('*', function(ev, msg)
    print('got event:', ev)
end)

time.at(1, function()
    ubus.send('test', { a = 1 })
end)

con:add('eco', {
    echo = {
        function(req, msg)
            if type(msg.text) ~= 'string' then
                return ubus.STATUS_INVALID_ARGUMENT
            end
            con:reply(req, msg)
        end, { text = ubus.STRING, x = ubus.INT32 }
    },
    defer = {
        function(req)
            time.sleep(1)
            con:reply(req, { message = 'deferred reply' })
        end
    }
})

time.at(1, function()
    local res = ubus.call('eco', 'echo', { text = 'hello' })
    print('call eco.echo:', res.text)

    res = ubus.call('eco', 'defer')
    print('call eco.defer:', res.message)
end)

eco.loop()
