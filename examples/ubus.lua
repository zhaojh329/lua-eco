#!/usr/bin/env eco

local ubus = require 'eco.ubus'
local time = require 'eco.time'
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

con:listen('*', function(ev, msg)
    print(ev, cjson.encode(msg))
end)

con:add('eco', {
    echo = {
        function(req, msg)
            con:reply(req, msg)
        end,
        {
            a = ubus.INT8
        }
    },
    defer = {
        function(req)
            con:reply(req, { message = 'wait for it 2s...' })

            local def_req = con:defer_request(req)

            time.at(2, function()
                con:reply(def_req, { message = 'done' })
                con:complete_deferred_request(def_req, 0)
                print('Deferred request complete')
            end)

            print("Call to function 'deferred'")
        end
    }
})
