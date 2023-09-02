#!/usr/bin/env eco

local ubus = require 'eco.ubus'
local time = require 'eco.time'
local sys = require 'eco.sys'

sys.signal(sys.SIGINT, function()
    print('\nGot SIGINT, now quit')
    eco.unloop()
end)

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
    res, err = ubus.call('eco', 'defer')
    if not res then
        print('call fail:', err)
        return
    end

    print(res[1].message)
    print(res[2].message)
end)


while true do
    time.sleep(1)
end
