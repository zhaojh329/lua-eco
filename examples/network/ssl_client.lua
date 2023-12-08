#!/usr/bin/env eco

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

while true do
    file.write(1, 'Please input: ')
    local data = file.read(0, 1024)

    s:send(data)

    local data, err = s:recv('*l')
    if not data then
        print(err)
        break
    end
    print('Read from server:', data)
end
