#!/usr/bin/env eco

local socket = require 'eco.socket'
local sys = require 'eco.sys'

sys.signal(sys.SIGINT, function()
    print('\nGot SIGINT, now quit')
    eco.unloop()
end)

local s, err = socket.listen_tcp(nil, 8080, { reuseaddr = true })
if not s then
    error(err)
end

print('listen...')

while true do
    local c, peer = s:accept()
    if not c then
        print(peer)
        break
    end

    print('new connection:', peer.ipaddr, peer.port)

    eco.run(function()
        while true do
            local data, err = c:recv('l')
            if not data then
                print(err)
                break
            end
            print('read:', data)
            c:send('I am eco:' .. data .. '\n')
        end
    end)
end
