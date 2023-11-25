#!/usr/bin/env eco

--[[
    to allow root to use icmp sockets, run:
    sysctl -w net.ipv4.ping_group_range="0 0"
--]]

local socket = require 'eco.socket'
local time = require 'eco.time'

local ICMP_HEADER_LEN = 8
local ICMP_ECHO = 8
local ICMP_ECHOREPLY = 0

local dest_ip = '127.0.0.1'
local local_id = math.random(0, 65535)
local local_seq = 1
local local_data = 'hello'

local function build_icmp_req()
    local data = {
        string.char(ICMP_ECHO), -- type
        '\0',        -- code
        '\0\0',      -- checksum
        '\0\0',      -- id: the kernel will assign it with local port
        string.char(local_seq >> 8, local_seq & 0xff),   -- sequence
        local_data
    }

    local_seq = local_seq + 1

    return table.concat(data)
end

local function parse_icmp_resp(data)
    if #data < ICMP_HEADER_LEN then
        return nil, 'invalid icmp resp'
    end

    local icmp_type = data:byte(1)
    local id_hi = data:byte(5)
    local id_lo = data:byte(6)
    local id = (id_hi << 8) + id_lo

    local seq_hi = data:byte(7)
    local seq_lo = data:byte(8)
    local seq = (seq_hi << 8) + seq_lo

    return icmp_type, id, seq, #data - ICMP_HEADER_LEN
end

local s, err = socket.icmp()
if not s then
    print(err)
    return
end

s:settimeout(5.0)

-- s:setoption('bindtodevice', 'eth0')

s:bind(nil, local_id)

print(string.format('PING %s, %d bytes of data.', dest_ip, #local_data))

while true do
    local _, err = s:sendto(build_icmp_req(), dest_ip, 0)
    if err then
        print('send fail:', err)
        break
    end

    local start = time.now()

    local resp, peer = s:recvfrom(1024)
    if not resp then
        print('recv fail:', peer)
        break
    end

    local elapsed = time.now() - start

    local icmp_type, id, seq, n = parse_icmp_resp(resp)

    if icmp_type then
        if icmp_type == ICMP_ECHOREPLY then
            if id == local_id then
                print(string.format('%d bytes from %s: icmp_seq=%d time=%.3f ms', n, dest_ip, seq, elapsed * 1000))
            end
        else
            print('Got ICMP packet with type ' .. icmp_type)
        end
    else
        print(id)
    end

    time.sleep(1.0)
end
