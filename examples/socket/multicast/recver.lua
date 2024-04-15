#!/usr/bin/env eco

local socket = require 'eco.socket'
local sys = require 'eco.sys'

sys.signal(sys.SIGINT, function()
    print('\nGot SIGINT, now quit')
    eco.unloop()
end)

local multicast_addr = '224.0.0.2'
local multicast_port = 8080

local sock, err = socket.listen_udp(nil, multicast_port)
if not sock then
    error(err)
end

sock:setoption('ip_add_membership', { multiaddr = multicast_addr })

while true do
    local data, peer = sock:recvfrom(1024)
    print('recvfrom:', peer.ipaddr, peer.port, data)
end
