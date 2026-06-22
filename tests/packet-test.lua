#!/usr/bin/env eco

local PACKET_PATH = 'packet.lua'

do
    local f = io.open(PACKET_PATH)
    if f then
        f:close()
    else
        PACKET_PATH = '../packet.lua'
    end
end

local packet = dofile(PACKET_PATH)
local socket = require 'eco.socket'

local saddr = '192.0.2.1'
local daddr = '198.51.100.2'
local payload = 'hello'
local udp = packet.udp(1234, 5678, payload, saddr, daddr)
local ip = packet.ip(saddr, daddr, socket.IPPROTO_UDP, udp)

local parsed = assert(packet.from_ip(ip))
assert(parsed.saddr == saddr, parsed.saddr)
assert(parsed.daddr == daddr, parsed.daddr)
assert(parsed.protocol == socket.IPPROTO_UDP)

local udp_parsed = assert(parsed:next())
assert(udp_parsed.source == 1234)
assert(udp_parsed.dest == 5678)
assert(udp_parsed.data == payload)

local eth = packet.ether('02:00:00:00:00:01', '02:00:00:00:00:02', socket.ETH_P_IP, ip)
local l2 = assert(packet.from_ether(eth))
local l3 = assert(l2:next())

assert(l3.saddr == saddr, l3.saddr)
assert(l3.daddr == daddr, l3.daddr)

print('packet tests passed')
