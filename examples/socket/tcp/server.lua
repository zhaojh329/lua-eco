#!/usr/bin/env eco

local socket = require 'eco.socket'
local eco = require 'eco'

local function handle_connection(c)
    while true do
        local data, err = c:read('l')
        if not data then
            print(err)
            break
        end
        print('read:', data)
        c:send('I am eco:' .. data .. '\n')
    end
end

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

    eco.run(handle_connection, c)
end
