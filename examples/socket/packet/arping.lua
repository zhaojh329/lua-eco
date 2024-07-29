#!/usr/bin/env eco

local socket = require 'eco.socket'
local packet = require 'eco.packet'
local link = require 'eco.ip'.link
local sys = require 'eco.sys'

sys.signal(sys.SIGINT, function()
    print('\nGot SIGINT, now quit')
    eco.unloop()
end)

if #arg < 2 then
    print('Usage:', arg[0], 'device', 'destination')
    os.exit(1)
end

local sock, err = socket.socket(socket.AF_PACKET, socket.SOCK_RAW, socket.htons(socket.ETH_P_ARP))
if not sock then
    error(err)
end

local function send_arp(device, destination)
    local res, err = link.get(device)
    if not res then
        error('get link:' .. err)
    end

    local sender_mac = res.address

    print(sender_mac .. '->ff:ff:ff:ff:ff:ff ARP', 'REQUEST ' .. destination)

    local arp_pkt = packet.arp(socket.ARPOP_REQUEST, sender_mac, nil, nil, destination)
    local eth_pkt = packet.ether(sender_mac, 'ff:ff:ff:ff:ff:ff', socket.ETH_P_ARP, arp_pkt)

    sock:sendto(eth_pkt, { ifname = device })
end

local device = arg[1]
local destination = arg[2]

send_arp(device, destination)

while true do
    local data, addr = sock:recvfrom(4096)
    if not data then
        error(addr)
    end

    local l2 = packet.from_ether(data)
    if l2.proto == socket.ETH_P_ARP then
        local l3 = l2:next()
        if l3 and l3.op == socket.ARPOP_REPLY then
            if l3.sip == destination then
                print(l2, l3)
                break
            end
        end
    end
end

os.exit(0)
