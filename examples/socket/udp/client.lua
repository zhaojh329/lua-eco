#!/usr/bin/env eco

local socket = require 'eco.socket'
local eco = require 'eco'

local sock, err = socket.connect_udp('127.0.0.1', 8080)
if not sock then
    error(err)
end

local stdin = eco.reader(0)

while true do
    print('Please input: ')

    local data = stdin:read('l')

    if data ~= '' then
        sock:send(data)

        local data, peer = sock:recvfrom(1024)

        print('recvfrom:', peer.ipaddr, peer.port, data)
    end
end
