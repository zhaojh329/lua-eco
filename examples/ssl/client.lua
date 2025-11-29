#!/usr/bin/env lua5.4

local bufio = require 'eco.bufio'
local file = require 'eco.file'
local sys = require 'eco.sys'
local ssl = require 'eco.ssl'
local eco = require 'eco'

sys.signal(sys.SIGINT, function()
    print('\nGot SIGINT, now quit')
    eco.unloop()
end)

eco.run(function()
    local s, err = ssl.connect('127.0.0.1', 8080, { insecure = true })
    if not s then
        error(err)
    end

    local b = bufio.new(0)

    while true do
        file.write(1, 'Please input: ')

        local data = b:read('L')

        if data ~= '\n' then
            s:send(data)

            local data, err = s:recv('l')
            if not data then
                print(err)
                break
            end
            print('Read from server:', data)
        end
    end
end)

eco.loop()
