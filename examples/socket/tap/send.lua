#!/usr/bin/env eco

local socket = require 'eco.socket'
local packet = require 'eco.packet'
local link = require 'eco.ip'.link
local eco = require 'eco'

local function dump_pkt(name)
    local sock, err = socket.socket(socket.AF_PACKET, socket.SOCK_RAW, socket.htons(socket.ETH_P_ALL))
    if not sock then
        error(err)
    end

    sock:bind({ ifname = name })

    local data, addr = sock:recvfrom(1500)
    if not data then
        error(addr)
    end

    local pkt, err = packet.from_ether(data)
    if not pkt then
        error('parse packet failed: ' .. err)
    end

    print(pkt.name, pkt.source, pkt.dest)

    while true do
        pkt = pkt:next()
        if not pkt then
            break
        end

        if pkt.name == 'IP' then
            print(pkt.name, pkt.saddr, '->', pkt.daddr)
        elseif pkt.name == 'UDP' then
            print(pkt.name, pkt.source, '->', pkt.dest, pkt.data)
        end
    end
end

local sock, name = socket.open_tun(nil, { tap = true, no_pi = true })
if not sock then
    error('create tun socket failed: ' .. name)
end

print('tap device name:', name)

link.set(name, { up = true })

eco.run(dump_pkt, name)

local udp_pkt = packet.udp(2345, 6766, 'hello')
local ip_pkt = packet.ip('192.168.1.2', '192.168.1.3', socket.IPPROTO_UDP, udp_pkt)
local eth_pkt = packet.ether('00:15:5d:de:28:a4', '00:15:5d:fc:5a:53', socket.ETH_P_IP, ip_pkt)

sock:send(eth_pkt)
