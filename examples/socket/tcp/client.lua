#!/usr/bin/env lua5.4

local socket = require 'eco.socket'
local bufio = require 'eco.bufio'
local file = require 'eco.file'
local sys = require 'eco.sys'
local eco = require 'eco'

sys.signal(sys.SIGINT, function()
    print('\nGot SIGINT, now quit')
    eco.unloop()
end)

eco.run(function()
    local s, err = socket.connect_tcp('127.0.0.1', 8080)
    if not s then
        error(err)
    end

    local stdin = bufio.new(0)

    local b = bufio.new(s)

    while true do
        file.write(1, 'Please input: ')

        local data = stdin:read('L')

        if data ~= '\n' then
            s:send(data)

            data, err = b:read('l')
            if not data then
                print(err)
                break
            end
            print('Read from server:', data)
        end
    end
end)

eco.loop()
