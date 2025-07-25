#!/usr/bin/env eco

local socket = require 'eco.socket'
local time = require 'eco.time'

local sock1, sock2 = socket.socketpair(socket.AF_UNIX, socket.SOCK_STREAM)
if not sock1 then
    error(sock2)
end

eco.run(function()
    while true do
        local data, err = sock1:read('L')
        if not data then
            print('error:', err)
            break
        end
        sock1:send('I recved: ' .. data)
    end
end)

sock2:send('Hello, lua-eco\n')

local data = sock2:read('l')
print(data)

sock2:close()

time.sleep(1)
