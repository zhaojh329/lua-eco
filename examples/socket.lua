#!/usr/bin/env eco

local socket = require 'eco.socket'
local file = require 'eco.file'
local sys = require 'eco.sys'

sys.signal(sys.SIGINT, function()
    print('\nGot SIGINT, now quit')
    eco.unloop()
end)

local sock = socket.tcp()

sock:setoption('reuseaddr', true)

local ok, err = sock:bind(nil, 8080)
if not ok then
    error(err)
end

sock:listen(128)

print('listen...')

while true do
    local c, peer = sock:accept()
    if not c then
        print(peer)
        break
    end

    print('new connection:', peer.ipaddr, peer.port)

    eco.run(function(c)
        while true do
            local data, err = c:recv(1024)
            if not data then
                print(err)
                break
            end
            print('read:', data)
            c:send('I am eco:' .. data)
        end
    end, c)
end
