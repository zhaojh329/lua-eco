#!/usr/bin/env eco

--[[
    to allow root to use icmp sockets, run:
    sysctl -w net.ipv4.ping_group_range="0 0"
--]]

local socket = require 'eco.socket'
local packet = require 'eco.packet'
local time = require 'eco.time'

local dest_ip = '127.0.0.1'
local local_id = math.random(0, 65535)
local local_data = 'hello'
local local_seq = 1

local s, err = socket.icmp()
if not s then
    print(err)
    return
end

-- s:setoption('bindtodevice', 'eth0')

s:bind(nil, local_id)

print(string.format('PING %s, %d bytes of data.', dest_ip, #local_data))

while true do
    local pkt = packet.icmp(socket.ICMP_ECHO, 0, 0, local_seq, 'hello')
    local_seq = local_seq + 1

    local _, err = s:sendto(pkt, dest_ip, 0)
    if err then
        print('send fail:', err)
        break
    end

    local start = time.now()

    local data, peer = s:recvfrom(1024, 5.0)
    if not data then
        print('recv fail:', peer)
        break
    end

    pkt = packet.from_icmp(data)

    if pkt.type == socket.ICMP_ECHOREPLY then
        if pkt.id == local_id then
            local elapsed = time.now() - start
            print(string.format('%d bytes from %s: icmp_seq=%d time=%.3f ms', #pkt.data, peer.ipaddr, pkt.sequence, elapsed * 1000))
        end
    else
        print('Got ICMP packet with type ' .. pkt.type)
    end

    time.sleep(1.0)
end
