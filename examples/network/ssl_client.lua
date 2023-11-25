#!/usr/bin/env eco

local bufio = require 'eco.bufio'
local file = require 'eco.file'
local ssl = require 'eco.ssl'
local sys = require 'eco.sys'

sys.signal(sys.SIGINT, function()
    print('\nGot SIGINT, now quit')
    eco.unloop()
end)

local s, err = ssl.connect('127.0.0.1', 8080, true)
if not s then
    error(err)
end

local b = bufio.new(0)

while true do
    file.write(1, 'Please input: ')

    local data = b:read('l')

    if data ~= '' then
        s:send(data)

        local data, err = s:recv(100)
        if not data then
            print(err)
            break
        end
        print('Read from server:', data)
    end
end
