#!/usr/bin/env eco

local ubus = require 'eco.ubus'
local sys = require 'eco.sys'
local cjson = require 'cjson'

sys.signal(sys.SIGINT, function()
    print('\nGot SIGINT, now quit')
    eco.unloop()
end)

local res = ubus.call('system', 'info')
if res then
    print(cjson.encode(res))
end

ubus.send('test', { a = 1 })

local con, err = ubus.connect()
if not con then
    error(err)
end

con:listen('*', function(con, ev, msg)
    print(ev, cjson.encode(msg))
end)

con:add('eco', {
    test = {
        function(con, req, msg)
            print(cjson.encode(msg))
            con:reply(req, { name = 'I am eco' })
        end,
        {
            a = ubus.INT8
        }
    }
})
