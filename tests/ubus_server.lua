#!/usr/bin/env eco

local ubus = require 'eco.ubus'
local time = require 'eco.time'
local sys = require 'eco.sys'

sys.signal(sys.SIGINT, function()
    print('\nGot SIGINT, now quit')
    eco.unloop()
end)

local con = ubus.connect()

local obj = con:add('eco', {
    echo = {
        function(req, msg)
            con:reply(req, msg)
        end
    }
})

con:listen('*', function(ev, msg)
    print('got event:', msg.j, ev)
    con:notify(obj, 'test', msg)
end)

while true do
    time.sleep(1000)
end
