#!/usr/bin/env eco

local socket = require 'eco.socket'
local time = require 'eco.time'

local sock1, sock2 = socket.socketpair(socket.AF_UNIX, socket.SOCK_DGRAM)
if not sock1 then
    error(sock2)
end

eco.run(function()
    while true do
        local data, err = sock1:read(100)
        if not data then
            print('error:', err)
            break
        end
        sock1:send('I recved: ' .. data)
        if data == 'q' then
            print('quit')
            break
        end
    end
end)

sock2:send('Hello, lua-eco')

local data = sock2:read(100)
print(data)

sock2:send('q')
time.sleep(1)
