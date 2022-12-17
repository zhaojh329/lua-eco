#!/usr/bin/env eco

local socket = require 'eco.socket'
local time = require 'eco.time'
local sys = require 'eco.sys'

sys.signal(sys.SIGPIPE, function()end)

sys.signal(sys.SIGINT, function()
    print('\nGot SIGINT, now quit')
    eco.unloop()
end)

local cnt = 0

while cnt < 100 do
    eco.run(function(i)
        local sock, err = socket.connect_tcp('127.0.0.1', 8080)
        if not sock then
            error(err)
        end

        while true do
            sock:send(i .. ': eco socket test\n')

            local data, err = sock:recv('*l')
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
