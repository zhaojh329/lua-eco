#!/usr/bin/env eco

local socket = require 'eco.socket'
local packet = require 'eco.packet'
local link = require 'eco.ip'.link
local sync = require 'eco.sync'
local time = require 'eco.time'
local sys = require 'eco.sys'

sys.signal(sys.SIGINT, function()
    print('\nGot SIGINT, now quit')
    eco.unloop()
end)

local function usage()
    print('Usage:', arg[0], 'eth0', '192.168.1.1/24')
    os.exit(1)
end

if #arg < 2 then
    usage()
end

local function get_dev_mac(dev)
    local res, err = link.get(dev)
    if not res then
        error('get link:' .. err)
    end

    return res.address
end

local function send_arp(sock, dev, sender_mac, destination)
    local arp_pkt = packet.arp(socket.ARPOP_REQUEST, sender_mac, nil, nil, destination)
    local eth_pkt = packet.ether(sender_mac, 'ff:ff:ff:ff:ff:ff', socket.ETH_P_ARP, arp_pkt)

    sock:sendto(eth_pkt, { ifname = dev })
end

local function generate_ips(subnet)
    local base_ip, cidr = subnet:match('([%d%.]+)/(%d+)')
    if not base_ip then
        return nil
    end

    local base = socket.ntohl(socket.inet_aton(base_ip))
    local mask = (~0 << (32 - cidr)) & 0xffffffff
    local network = base & mask
    local broadcast = network | ((-(mask & 0xffffffff) - 1) & 0xffffffff)
    local curr_ip  = network

    local ips = {}
    local cnt = 0

    while curr_ip < broadcast do
        local ip = socket.inet_ntoa(socket.htonl(curr_ip))
        ips[ip]= true
        cnt = cnt + 1
        curr_ip = curr_ip + 1
    end

    return ips, cnt
end

local device = arg[1]
local destination = arg[2]

local sender_mac = get_dev_mac(device)

local ips, cnt = generate_ips(destination)
if not ips or cnt < 1 then
    usage()
end

local wg = sync.waitgroup()

wg:add(cnt)

local sock, err = socket.socket(socket.AF_PACKET, socket.SOCK_RAW, socket.htons(socket.ETH_P_ARP))
if not sock then
    error(err)
end

eco.run(function()
    while true do
        local data, addr = sock:recvfrom(4096)
        if not data then
            error(addr)
        end

        local l2 = packet.from_ether(data)
        if l2.proto == socket.ETH_P_ARP then
            local l3 = l2:next()
            if l3 and l3.op == socket.ARPOP_REPLY then
                if ips[l3.sip] then
                    print(l3.sha, l3.sip)
                    wg:done()
                end
            end
        end
    end
end)

eco.run(function()
    for ip in pairs(ips) do
        send_arp(sock, device, sender_mac, ip)
        time.sleep(0.01)
    end
end)

wg:wait(5)
os.exit(0)
