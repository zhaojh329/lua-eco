#!/usr/bin/env eco

--[[
    to allow root to use icmp sockets, run:
    sysctl -w net.ipv4.ping_group_range="0 0"
--]]

local socket = require 'eco.socket'
local time = require 'eco.time'
local bit = require 'bit'

local ICMP_ECHO = 8
local ICMP_ECHOREPLY = 0

local timeout = 5.0

local local_id = 12
local local_seq = 1

local function build_icmp_req()
    local data = {
        string.char(ICMP_ECHO), -- type
        string.char(0),         -- code
        string.char(0, 0),      -- checksum
        string.char(0, 0),      -- id: the kernel will assign it with local port
        string.char(bit.rshift(local_seq, 8), bit.band(local_seq, 0xff)),   -- sequence
        'Hello'
    }

    print('send ICMP ECHO request id=' .. local_id, 'seq=' .. local_seq)

    local_seq = local_seq + 1

    return table.concat(data)
end

local function parse_icmp_resp(data)
    local icmp_type = data:byte(1)
    local id_hi = data:byte(5)
    local id_lo = data:byte(6)
    local id = bit.lshift(id_hi, 8) + id_lo

    local seq_hi = data:byte(7)
    local seq_lo = data:byte(8)
    local seq = bit.lshift(seq_hi, 8) + seq_lo

    return icmp_type, id, seq
end

local s, err = socket.icmp()
if not s then
    print(err)
    return
end

s:bind(nil, local_id)

while true do
    local _, err = s:sendto(build_icmp_req(), '127.0.0.1', 0)
    if err then
        print('send fail:', err)
        break
    end

    local resp, peer = s:recvfrom(1024, timeout)
    if not resp then
        print('recv fail:', err)
        break
    end

    local icmp_type, id, seq = parse_icmp_resp(resp)

    if icmp_type == ICMP_ECHOREPLY then
        print('recv ICMP ECHO reply   id=' .. id, 'seq=' .. seq, 'from ' .. peer.ipaddr)
    else
        print('Got ICMP packet with type ' .. icmp_type)
    end

    time.sleep(1.0)
end
