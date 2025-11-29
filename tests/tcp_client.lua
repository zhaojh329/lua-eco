#!/usr/bin/env lua5.4

local socket = require 'eco.socket'
local time = require 'eco.time'
local sys = require 'eco.sys'
local eco = require 'eco'

sys.signal(sys.SIGINT, function()
    print('\nGot SIGINT, now quit')
    eco.unloop()
end)

local cnt = 0

eco.run(function ()
    while cnt < 100 do
        eco.run(function(i)
            local sock, err = socket.connect_tcp('127.0.0.1', 8080)
            if not sock then
                error(err)
            end

            while true do
                sock:send(i .. ': eco socket test')

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
end)

eco.loop()
