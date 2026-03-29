#!/usr/bin/env eco

local socket = require 'eco.socket'
local eco = require 'eco'

local multicast_addr = '224.0.0.2'
local multicast_port = 8080

local sock, err = socket.udp()
if not sock then
    error(err)
end

local stdin = eco.reader(0)

while true do
    print('Please input:')

    local data = stdin:read('l')

    if data ~= '' then
        sock:sendto(data, multicast_addr, multicast_port)
    end
end
