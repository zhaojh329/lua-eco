#!/usr/bin/env eco

local socket = require 'eco.socket'
local bufio = require 'eco.bufio'
local file = require 'eco.file'
local sys = require 'eco.sys'

sys.signal(sys.SIGINT, function()
    print('\nGot SIGINT, now quit')
    eco.unloop()
end)

local s, err = socket.connect_tcp('127.0.0.1', 8080)
if not s then
    error(err)
end

local b = bufio.new(0)

while true do
    file.write(1, 'Please input: ')

    local data = b:read('L')

    if data ~= '\n' then
        s:send(data)

        data, err = s:recv('l')
        if not data then
            print(err)
            break
        end
        print('Read from server:', data)
    end
end
