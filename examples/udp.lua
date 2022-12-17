#!/usr/bin/env eco

local socket = require 'eco.socket'
local file = require 'eco.file'
local sys = require 'eco.sys'

sys.signal(sys.SIGINT, function()
    print('\nGot SIGINT, now quit')
    eco.unloop()
end)

local sock = socket.udp()

local ok, err = sock:bind(nil, 8080)
if not ok then
    error(err)
end

while true do
    local data, addr = sock:recvfrom(1024)
    if not data then
        print('recvfrom fail:', addr)
        break
    end

    print('recvfrom:', addr.ipaddr, addr.port, data)
    sock:sendto('I am eco', addr.ipaddr, addr.port)
end
