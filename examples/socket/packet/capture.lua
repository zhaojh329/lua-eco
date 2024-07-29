#!/usr/bin/env eco

local socket = require 'eco.socket'
local packet = require 'eco.packet'
local link = require 'eco.ip'.link
local sys = require 'eco.sys'

sys.signal(sys.SIGINT, function()
    print('\nGot SIGINT, now quit')
    eco.unloop()
end)

local function usage()
    print('usage: ' .. arg[0], '[options]')
    print('Available options are:')
    print('  -i device     Capture packets on the specified device')
    print('  -p            Turn on the promiscuous mode of device')
    print('  -proto        Specifies the Layer 3 protocol to capture(8021q, arp, ip, ipv6)')
    print('  -protocol     Specifies the Layer 4 protocol to capture(icmp, icmpv6, tcp, udp)')
    print('  -sport        Specifies the source port for UDP or TCP')
    print('  -dport        Specifies the source port for UDP or TCP')
    print('  -data-match   Specifies the data match pattern for UDP or TCP')
    os.exit(1)
end

local function parse_arg()
    local params = {}
    local i = 1

    while i <= #arg do
        local name = arg[i]
        if name:sub(1, 1) ~= '-' then
            usage()
        end

        name = name:sub(2)

        if name == 'i' then
            local dev = arg[i + 1]
            if not dev then
                usage()
            end
            params.dev = dev
            i = i + 1
        elseif name == 'p' then
            if not params.dev then
                usage()
            end
            params.promisc = true
        elseif name == 'proto' then
            local proto = arg[i + 1] or ''

            proto = proto:upper()

            if proto == '8021Q' then
                proto = socket.ETH_P_8021Q
            elseif proto == 'ARP' then
                proto = socket.ETH_P_ARP
            elseif proto == 'IP' then
                proto = socket.ETH_P_IP
            elseif proto == 'IPV6' then
                proto = socket.ETH_P_IPV6
            else
                usage()
            end
            params.proto = proto
            i = i + 1
        elseif name == 'protocol' then
            local protocol = arg[i + 1] or ''

            protocol = protocol:upper()

            if protocol == 'ICMP' then
                protocol = socket.IPPROTO_ICMP
            elseif protocol == 'ICMPV6' then
                protocol = socket.IPPROTO_ICMPV6
            elseif protocol == 'TCP' then
                protocol = socket.IPPROTO_TCP
            elseif protocol == 'UDP' then
                protocol = socket.IPPROTO_UDP
            else
                usage()
            end
            params.protocol = protocol
            i = i + 1
        elseif name == 'sport' then
            local sport = tonumber(arg[i + 1] or '')
            if not sport then
                usage()
            end
            params.sport = sport
            i = i + 1
        elseif name == 'dport' then
            local dport = tonumber(arg[i + 1] or '')
            if not dport then
                usage()
            end
            params.dport = dport
            i = i + 1
        elseif name == 'data-match' then
            local match = arg[i + 1]
            if not match then
                usage()
            end

            match = match:gsub('.', function (c)
                return '%' .. c
            end)

            params.match = match
            i = i + 1
        else
            usage()
        end
        i = i + 1
    end

    return params
end

local sock, err = socket.socket(socket.AF_PACKET, socket.SOCK_RAW, socket.htons(socket.ETH_P_ALL))
if not sock then
    error(err)
end

local link_type

local params = parse_arg()

if params.dev then
    local ok, err = sock:bind({ ifname = params.dev })
    if not ok then
        print(err)
        error(err)
    end

    if params.promisc then
        ok, err = sock:setoption('packet_add_membership', { ifname = params.dev, type = socket.PACKET_MR_PROMISC })
        if not ok then
            error(err)
        end
    end

    link_type = link.get(params.dev).type
end

local function dump_pkt(data, addr)
    local pkt

    if link_type == socket.ARPHRD_ETHER or link_type == socket.ARPHRD_LOOPBACK then
        pkt = packet.from_ether(data)
    elseif link_type == socket.ARPHRD_IEEE80211_RADIOTAP then
        pkt = packet.from_radiotap(data)
    else
        return
    end

    if params.proto and pkt.proto ~= params.proto then
        return
    end

    local chunks = { tostring(pkt) }

    while true do
        pkt = pkt:next()
        if not pkt then
            break
        end

        if pkt.proto then
            if params.proto and pkt.proto ~= params.proto then
                return
            end
        elseif pkt.protocol then
            if params.protocol and pkt.protocol ~= params.protocol then
                return
            end
        end

        if pkt.name == 'TCP' or pkt.name == 'UDP' then
            if params.sport and pkt.source ~= params.sport then
                return
            end

            if params.dport and pkt.dest ~= params.dport then
                return
            end

            if params.match then
                if not pkt.data:match(params.match) then
                    return
                end
            end
        end

        chunks[#chunks+1] = tostring(pkt)
    end

    print(addr.ifname .. ' ' .. table.concat(chunks, ' '))
end

while true do
    local data, addr = sock:recvfrom(4096)
    if not data then
        error(addr)
    end

    if not params.dev then
        link_type = link.get(addr.ifname).type
    end

    dump_pkt(data, addr)
end
