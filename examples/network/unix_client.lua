#!/usr/bin/env eco

local socket = require 'eco.socket'
local file = require 'eco.file'
local sys = require 'eco.sys'

sys.signal(sys.SIGINT, function()
    print('\nGot SIGINT, now quit')
    eco.unloop()
end)

local sock, err = socket.connect_unix('/tmp/eco.sock', '/tmp/client.sock')
if not sock then
    error(err)
end

while true do
    file.write(0, 'Please input: ')
    local data = file.read(0, 1024)

    sock:send(data)

    local data, err = sock:recv('*l')
    if not data then
        print(err)
        break
    end
    print('Read from server:', data)
end
