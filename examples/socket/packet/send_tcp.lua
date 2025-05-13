#!/usr/bin/env eco

local socket = require 'eco.socket'
local packet = require 'eco.packet'

local sock<close>, err = socket.socket(socket.AF_PACKET, socket.SOCK_RAW, socket.htons(socket.ETH_P_IP))
if not sock then
    error(err)
end

local saddr = '192.168.1.2'
local daddr = '192.168.1.3'

local tcp_pkt = packet.tcp(2345, 6766, 1, 2, { syn = true }, 0, saddr, daddr, 'hello')
local ip_pkt = packet.ip(saddr, daddr, socket.IPPROTO_TCP, tcp_pkt)
local eth_pkt = packet.ether('00:15:5d:de:28:a4', '00:15:5d:fc:5a:53', socket.ETH_P_IP, ip_pkt)

sock:sendto(eth_pkt, { ifname = 'eth0' })

os.exit(0)
