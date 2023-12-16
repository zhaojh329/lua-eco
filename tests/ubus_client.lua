#!/usr/bin/env eco

local ubus = require 'eco.ubus'
local time = require 'eco.time'
local sys = require 'eco.sys'

sys.signal(sys.SIGINT, function()
    print('\nGot SIGINT, now quit')
    eco.unloop()
end)

local i = 0

eco.run(function()
    while true do
        local res, err = ubus.call('eco', 'echo', { text = 'hello', i = i })
        if not res then
            print('call error:', err)
            break
        end
        print(res.i, res.text)
        i = i + 1
        time.sleep(0.001)
    end
end)

local j = 0
eco.run(function()
    while true do
        ubus.send('test', { j = j })
        j = j + 1
        time.sleep(0.001)
    end
end)
