-- SPDX-License-Identifier: MIT
-- Author: Jianhui Zhao <zhaojh329@gmail.com>

local socket = require 'eco.socket'
local packet = require 'eco.packet'
local time = require 'eco.time'
local dns = require 'eco.dns'

--- Network utilities.
--
-- Currently this module provides simple ICMP echo (ping) helpers for both
-- IPv4 and IPv6.
--
-- @module eco.net

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

--- Options table for @{net.ping} / @{net.ping6}.
-- @table PingOptions
-- @tfield[opt=5.0] number timeout Receive timeout in seconds.
-- @tfield[opt="hello"] string data ICMP payload.
-- @tfield[opt] number mark Set `SO_MARK` on the underlying socket (Linux).
-- @tfield[opt] string device Bind socket to a specific interface (e.g. `"eth0"`).
-- @tfield[opt] table nameservers DNS servers used for name resolution.
--   Each entry is typically an IP string (e.g. `{ "1.1.1.1", "8.8.8.8" }`).

--- Send an ICMP echo request (IPv4).
--
-- If `host` is a domain name, it will be resolved using DNS A records.
--
-- @function ping
-- @tparam string host IPv4 address or domain name.
-- @tparam[opt] PingOptions opts Options table.
-- @treturn number Round-trip time in seconds.
-- @treturn[2] nil On failure.
-- @treturn[2] string err Error message.
-- @usage
-- local net = require 'eco.net'
-- local rtt, err = net.ping('8.8.8.8', { timeout = 1 })
-- print(rtt or err)
function M.ping(host, opts)
   return ping_any(host, opts, false)
end

--- Send an ICMP echo request (IPv6).
--
-- If `host` is a domain name, it will be resolved using DNS AAAA records.
--
-- @function ping6
-- @tparam string host IPv6 address or domain name.
-- @tparam[opt] PingOptions opts Options table.
-- @treturn number Round-trip time in seconds.
-- @treturn[2] nil On failure.
-- @treturn[2] string err Error message.
function M.ping6(host, opts)
    return ping_any(host, opts, true)
end

return M
