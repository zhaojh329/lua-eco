#!/usr/bin/env eco

local ssl = require 'eco.ssl'
local eco = require 'eco'

local s, err = ssl.connect('127.0.0.1', 8080, { insecure = true })
if not s then
    error(err)
end

local stdin = eco.reader(0)

while true do
    print('Please input: ')

    local data = stdin:read('L')

    if data ~= '\n' then
        s:send(data)

        data, err = s:recv(1024)
        if not data then
            print(err)
            break
        end
        print('Read from server:', data)
    end
end
