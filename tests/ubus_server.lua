#!/usr/bin/env lua5.4

local ubus = require 'eco.ubus'
local time = require 'eco.time'
local sys = require 'eco.sys'
local eco = require 'eco'

sys.signal(sys.SIGINT, function()
    print('\nGot SIGINT, now quit')
    eco.unloop()
end)

local con = ubus.connect()

local obj = con:add('eco', {
    echo = {
        function(_, req, msg)
            con:reply(req, msg)
        end
    }
})

con:listen('*', function(_, ev, msg)
    print('got event:', msg.j, ev)
    con:notify(obj, 'test', msg)
end)

eco.loop()
