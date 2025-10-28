-- SPDX-License-Identifier: MIT
-- Author: Jianhui Zhao <zhaojh329@gmail.com>

local socket = require 'eco.socket'
local packet = require 'eco.packet'
local time = require 'eco.time'
local dns = require 'eco.dns'

local M = {}

local function ping_any(host, opts, ipv6)
    local dest_ip

    opts = opts or {}

    local is_ip_address = socket.is_ipv4_address
    local dns_type = dns.TYPE_A
    local socket_icmp = socket.icmp
    local reply_type = socket.ICMP_ECHOREPLY

    if ipv6 then
        is_ip_address = socket.is_ipv6_address
        dns_type = dns.TYPE_AAAA
        socket_icmp = socket.icmp6
        reply_type = socket.ICMPV6_ECHO_REPLY
    end

    if is_ip_address(host) then
        dest_ip = host
    else
        local answers, err = dns.query(host, {
            type = dns_type,
            mark = opts.mark,
            device = opts.device,
            nameservers = opts.nameservers
        })
        if not answers then
            return nil, 'resolve "' .. host .. '" fail: ' .. err
        end

        for _, a in ipairs(answers) do
            if a.type == dns_type then
                dest_ip = a.address
                break
            end
        end

        if not dest_ip then
            return nil, 'resolve "' .. host .. '" fail: not found'
        end
    end

    local s, err = socket_icmp()
    if not s then
        return nil, err
    end

    if opts.device then
        s:setoption('bindtodevice', opts.device)
    end

    if opts.mark then
        s:setoption('mark', opts.mark)
    end

    local local_id = math.random(0, 65535)
    local local_seq = 1

    s:bind(nil, local_id)

    local pkt

    if ipv6 then
        pkt = packet.icmp6(socket.ICMPV6_ECHO_REQUEST, 0, 0, local_seq, opts.data or 'hello')
    else
        pkt = packet.icmp(socket.ICMP_ECHO, 0, 0, local_seq, opts.data or 'hello')
    end

    _, err = s:sendto(pkt, dest_ip, 0)
    if err then
        return nil, err
    end

    local start = time.now()

    local data, peer = s:recvfrom(1024, opts.timeout or 5.0)
    if not data then
        return nil, peer
    end

    if ipv6 then
        pkt = packet.from_icmp6(data)
    else
        pkt = packet.from_icmp(data)
    end

    if pkt.type == reply_type then
        if pkt.id == local_id then
            return time.now() - start
        else
            return nil, ("unexpected icmp id: got %d, expected %d"):format(pkt.id, local_id)
        end
    else
        return nil, 'unexpected type ICMP ' .. pkt.type
    end
end

--[[
    host: Target host to ping, can be an IPv4 address (e.g., "8.8.8.8") or a domain name (e.g., "example.com").
    opts: A table containing optional parameters:
        timeout: A number specifying the maximum time (in seconds) to wait for a reply; defaults to 5.0.
        data: A string used as the ICMP payload; defaults to "hello".
        mark: A number used to set SO_MARK on the underlying socket.
        device: A string used to bind the socket to a specific network interface (e.g., "eth0").
        nameservers: A table of DNS server addresses (e.g., {"1.1.1.1", "8.8.8.8"}) used for domain resolution.

    In case of failure, the function returns nil followed by an error message.
    If successful, returns a number representing the round-trip time (RTT) in seconds (as a high-precision float).
--]]
function M.ping(host, opts)
   return ping_any(host, opts, false)
end

function M.ping6(host, opts)
    return ping_any(host, opts, true)
end

return M
