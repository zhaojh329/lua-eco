#!/usr/bin/env eco

local socket = require 'eco.socket'
local eco = require 'eco'

local s, err = socket.connect_tcp('127.0.0.1', 8080)
if not s then
    error(err)
end

local stdin = eco.reader(0)

while true do
    print('Please input: ')

    local data = stdin:read('L')

    if data ~= '\n' then
        s:send(data)

        data, err = s:read('l')
        if not data then
            print(err)
            break
        end
        print('Read from server:', data)
    end
end
