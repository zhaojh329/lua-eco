#!/usr/bin/env eco

local socket = require 'eco.socket'
local eco = require 'eco'

local sock, err = socket.listen_udp(nil, 8080)
if not sock then
    error(err)
end

while true do
    local data, peer = sock:recvfrom(1024)
    if not data then
        print(peer)
        break
    end
    print('recvfrom:', peer.ipaddr, peer.port, data)
    sock:sendto('I am eco', peer.ipaddr, peer.port)
end
