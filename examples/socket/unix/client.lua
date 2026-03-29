#!/usr/bin/env eco

local socket = require 'eco.socket'
local eco = require 'eco'

local s, err = socket.connect_unix('/tmp/eco.sock')
if not s then
    error(err)
end

local stdin = eco.reader(0)

while true do
    print('Please input:')

    local data = stdin:read('l')

    if data ~= '' then
        s:send(data)

        data, err = s:recv(100)
        if not data then
            print(err)
            break
        end
        print('Read from server:', data)
    end
end
