#!/usr/bin/env eco

local ubus = require 'eco.ubus'
local time = require 'eco.time'
local sys = require 'eco.sys'

sys.signal(sys.SIGINT, function()
    print('\nGot SIGINT, now quit')
    eco.unloop()
end)

-- Set the global timeout time, defaults to 30.0
ubus.settimeout(30.0)

local res, err = ubus.call('system', 'board')
if not res then
    print('call system.board fail:', err)
else
    print(res.model)
end

local con, err = ubus.connect()
if not con then
    error(err)
end

-- Set the timeout time for this connection, defaults to 30.0
con:settimeout(30.0)

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
    res = ubus.call('eco', 'echo', { text = 'hello' })
    print('call eco.echo:', res.text)

    res = ubus.call('eco', 'defer')
    print('call eco.defer:', res.message)
end)

while true do
    time.sleep(1)
end
