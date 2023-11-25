#!/usr/bin/env eco

local time = require 'eco.time'
local ssl = require 'eco.ssl'
local sys = require 'eco.sys'

sys.signal(sys.SIGINT, function()
    print('\nGot SIGINT, now quit')
    eco.unloop()
end)

local cnt = 0

while cnt < 100 do
    eco.run(function(i)
        local sock, err = ssl.connect('127.0.0.1', 8080, true)
        if not sock then
            error(err)
        end

        while true do
            sock:send(i .. ': eco ssl test')

            local data, err = sock:recv(100)
            if not data then
                print(err)
                sock:close()
                return
            end
            print(data)
        end
    end, cnt)

    cnt = cnt + 1

    time.sleep(0.01)
end
