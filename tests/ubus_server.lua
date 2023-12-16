#!/usr/bin/env eco

local ubus = require 'eco.ubus'
local time = require 'eco.time'
local sys = require 'eco.sys'

sys.signal(sys.SIGINT, function()
    print('\nGot SIGINT, now quit')
    eco.unloop()
end)

local con = ubus.connect()

con:add('eco', {
    echo = {
        function(req, msg)
            con:reply(req, msg)
        end
    }
})

con:listen('*', function(ev, msg)
    print('got event:', msg.j, ev)
end)

while true do
    time.sleep(1)
end