#!/usr/bin/env eco

local socket = require 'eco.socket'
local packet = require 'eco.packet'

local sock, err = socket.socket(socket.AF_PACKET, socket.SOCK_RAW, socket.htons(socket.ETH_P_IP))
if not sock then
    error(err)
end

local udp_pkt = packet.udp(2345, 6766, 'hello')
local ip_pkt = packet.ip('192.168.1.2', '192.168.1.3', socket.IPPROTO_UDP, udp_pkt)
local eth_pkt = packet.ether('00:15:5d:de:28:a4', '00:15:5d:fc:5a:53', socket.ETH_P_IP, ip_pkt)

sock:sendto(eth_pkt, { ifname = 'eth0' })
sock:close()

os.exit(0)
