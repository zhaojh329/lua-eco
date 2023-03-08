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
            if type(msg.text) ~= 'string' then
                return ubus.STATUS_INVALID_ARGUMENT
            end
            con:reply(req, msg)
        end, { text = ubus.STRING }
    },
    defer = {
        function(req)
            con:reply(req, { message = 'deferred reply' })
            time.sleep(1)
            con:reply(req, { message = 'deferred done' })
        end
    }
})

time.at(1, function()
    local res1, res2 = ubus.call('eco', 'defer')
    print(cjson.encode(res1))
    print(cjson.encode(res2))
end):start()

while true do
    time.sleep(1)
end
