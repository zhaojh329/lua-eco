-- SPDX-License-Identifier: MIT
-- Author: Jianhui Zhao <zhaojh329@gmail.com>

--- Packet encoding and decoding helpers.
--
-- This module provides:
--
-- - decoders for common L2/L3/L4 packets (Ethernet, IPv4/IPv6, ARP, ICMP,
--   TCP, UDP, and selected 802.11 radiotap frames)
-- - encoders for raw packets used with raw sockets
--
-- Most `from_*` functions return a packet object that supports `pkt:next()` to
-- decode the next protocol layer.
--
-- @module eco.packet

local hex = require 'eco.encoding.hex'
local nl80211 = require 'eco.nl80211'
local socket = require 'eco.socket'

local M = {}

local methods_decap = {}

local mtable_decap = {
    __index = methods_decap
}

local protos = {
    [socket.ETH_P_8021Q] = {
        name = '8021Q',
        next = function(data)
            if #data < 4 then
                return nil, 'not a valid 8021Q packet'
            end

            local tci = string.unpack('>I2', data:sub(1))

            return setmetatable({
                name = '8021Q',
                pri = tci >> 13,
                vid = tci & 0xfff,
                proto = string.unpack('>I2', data:sub(3)),
                data = data:sub(5)
            }, mtable_decap)
        end
    },
    [socket.ETH_P_ARP] = {
        name = 'ARP',
        next = function(data)
            if #data < 8 then
                return nil, 'not a valid ARP packet'
            end

            local pkt = {
                name = 'ARP',
                ar_hrd = string.unpack('>I2', data:sub(1)),
                ar_pro = string.unpack('>I2', data:sub(3)),
                ar_hln = data:byte(5),
                ar_pln = data:byte(6),
                op = string.unpack('>I2', data:sub(7))
            }

            if #data < 8 + pkt.ar_hln * 2 + pkt.ar_pln * 2 then
                return nil, 'not a valid ARP packet'
            end

            if pkt.ar_hrd == socket.ARPHRD_ETHER and pkt.ar_pro == socket.ETH_P_IP then
                pkt.sha = hex.encode(data:sub(9, 14), ':')
                pkt.sip = socket.inet_ntop(socket.AF_INET, data:sub(15))
                pkt.tha = hex.encode(data:sub(19, 24), ':')
                pkt.tip = socket.inet_ntop(socket.AF_INET, data:sub(25))
            end

            return setmetatable(pkt, mtable_decap)
        end
    },
    [socket.ETH_P_IP] = {
        name = 'IP',
        next = function(data)
            local ihl = 20

            if #data < ihl then
                return nil, 'not a valid IPv4 packet'
            end

            local byte1 = data:byte(1)
            local version = byte1 >> 4
            ihl = byte1 & 0xf

            if #data < ihl * 4 then
                return nil, 'not a valid IPv4 packet'
            end

            return setmetatable({
                name = 'IP',
                version = version,
                ihl = ihl,
                tos = data:byte(2),
                tot_len = string.unpack('>I2', data:sub(3)),
                id = string.unpack('>I2', data:sub(5)),
                frag_off = string.unpack('>I2', data:sub(7)),
                ttl = data:byte(9),
                protocol = data:byte(10),
                check = string.unpack('>I2', data:sub(12)),
                saddr = socket.inet_ntop(socket.AF_INET, data:sub(17)),
                daddr = socket.inet_ntop(socket.AF_INET, data:sub(13)),
                data = data:sub(ihl * 4 + 1)
            }, mtable_decap)
        end
    },
    [socket.ETH_P_IPV6] = {
        name = 'IPV6',
        next = function(data)
            if #data < 40 then
                return nil, 'not a valid IPV6 packet'
            end

            local byte1 = data:byte(1)
            local version = byte1 >> 4
            local priority = byte1 & 0xf

            local pkt = {
                name = 'IPV6',
                version = version,
                priority = priority,
                payload_len = string.unpack('>I2', data:sub(5)),
                nexthdr = data:byte(7),
                hop_limit = data:byte(8),
                saddr = socket.inet_ntop(socket.AF_INET6, data:sub(9)),
                daddr = socket.inet_ntop(socket.AF_INET6, data:sub(25)),
                data = data:sub(41)
            }

            local nexthdr = pkt.nexthdr

            if nexthdr == socket.IPPROTO_TCP or nexthdr == socket.IPPROTO_UDP then
                pkt.protocol = nexthdr
            elseif nexthdr == 4 then
                pkt.proto = socket.ETH_P_IP     -- IPv4 in IPv6
            elseif nexthdr == 41 then
                pkt.proto = socket.ETH_P_IPV6   -- IPv6 in IPv6
            end

            return setmetatable(pkt, mtable_decap)
        end
    }
}

local protocols = {
    [socket.IPPROTO_ICMP] = {
        name = 'ICMP',
        next = function(data)
            if #data < 8 then
                return nil, 'not a valid ICMP packet'
            end

            local typ, code = data:byte(1, 2)

            local pkt = {
                name = 'ICMP',
                type = typ,
                code = code,
                checksum = string.unpack('>I2', data:sub(3))
            }

            if typ == socket.ICMP_ECHO or typ == socket.ICMP_ECHOREPLY then
                pkt.id = string.unpack('>I2', data:sub(5))
                pkt.sequence = string.unpack('>I2', data:sub(7))
            elseif typ == socket.ICMP_REDIRECT then
                pkt.gateway = socket.inet_ntop(socket.AF_INET, data:sub(5))
            end

            pkt.data = data:sub(9)

            return setmetatable(pkt, mtable_decap)
        end
    },
    [socket.IPPROTO_ICMPV6] = {
        name = 'ICMPV6',
        next = function(data)
            if #data < 8 then
                return nil, 'not a valid ICMPV6 packet'
            end

            local typ, code = data:byte(1, 2)
            local pkt = {
                name = 'ICMPV6',
                type = typ,
                code = code,
                checksum = string.unpack('>I2', data:sub(3))
            }

            if typ == socket.ICMPV6_ECHO_REQUEST or typ == socket.ICMPV6_ECHO_REPLY then
                pkt.id = string.unpack('>I2', data:sub(5))
                pkt.sequence = string.unpack('>I2', data:sub(7))
            end

            pkt.data = data:sub(9)

            return setmetatable(pkt, mtable_decap)
        end
    },
    [socket.IPPROTO_TCP] = {
        name = 'TCP',
        next = function(data, self)
            local thl = 20

            if #data < thl then
                return nil, 'not a valid TCP packet'
            end

            local doff = data:byte(13) >> 4
            thl = doff * 4
            local len = self.tot_len - self.ihl * 4 - thl
            local byte14 = data:byte(14)

            return setmetatable({
                name = 'TCP',
                source = string.unpack('>I2', data),
                dest = string.unpack('>I2', data:sub(3)),
                seq = string.unpack('>I4', data:sub(5)),
                ack_seq = string.unpack('>I4', data:sub(9)),
                doff = doff,
                cwr = (byte14 >> 7) & 0x1 == 1,
                ece = (byte14 >> 6) & 0x1 == 1,
                urg = (byte14 >> 5) & 0x1 == 1,
                ack = (byte14 >> 4) & 0x1 == 1,
                psh = (byte14 >> 3) & 0x1 == 1,
                rst = (byte14 >> 2) & 0x1 == 1,
                syn = (byte14 >> 1) & 0x1 == 1,
                fin = byte14 & 0x1 == 1,
                window = string.unpack('>I2', data:sub(15)),
                check = string.unpack('>I2', data:sub(17)),
                urg_ptr = string.unpack('>I2', data:sub(19)),
                data = data:sub(thl + 1, thl + len)
            }, mtable_decap)
        end
    },
    [socket.IPPROTO_UDP] = {
        name = 'UDP',
        next = function(data)
            local uhl = 8

            if #data < uhl then
                return nil, 'not a valid UDP packet'
            end

            local len = string.unpack('>I2', data:sub(5))
            local data_len = len - uhl

            return setmetatable({
                name = 'UDP',
                source = string.unpack('>I2', data),
                dest = string.unpack('>I2', data:sub(3)),
                len = len,
                check = string.unpack('>I2', data:sub(7)),
                data = data:sub(uhl + 1, uhl + data_len)
            }, mtable_decap)
        end
    }
}

local tostrings = {
    ['80211'] = function(self)
        local typ, subtype = self.type, self.subtype
        local name = nl80211.ftype_name(typ, subtype)
        local fields = {}

        if self.addr1 then
            if self.addr2 then
                fields[#fields + 1] = self.addr2 .. '->' .. self.addr1
            else
                fields[#fields + 1] = self.addr1
            end
        end

        if name then
            fields[#fields + 1] = name
        else
            fields[#fields + 1] = 'type ' .. string.format('0x%02x', typ)
            fields[#fields + 1] = 'subtype ' .. string.format('0x%02x', subtype)
        end

        if typ == nl80211.FTYPE_MGMT then
            if self.beacon_interval then
                fields[#fields + 1] = 'BI=' .. self.beacon_interval
            end

            if self.ssid then
                fields[#fields + 1] = 'SSID="' .. self.ssid .. '"'
            end
        end

        return table.concat(fields, ' ')
    end,
    ['ETHER'] = function(self)
        local proto = self.proto
        local p = protos[self.proto]
        return self.source .. '->' .. self.dest .. ' ' .. (p and p.name or proto)
    end,
    ['8021Q'] = function(self)
        local proto = self.proto
        local p = protos[self.proto]
        return 'pri ' .. self.pri .. ' vid ' .. self.vid .. ' ' .. (p and p.name or proto)
    end,
    ['ARP'] = function(self)
        if self.ar_hrd == socket.ARPHRD_ETHER and self.ar_pro == socket.ETH_P_IP then
            if self.op == socket.ARPOP_REQUEST then
                return string.format('Request who-has %s (%s) tell %s', self.tip, self.tha, self.sip)
            else
                return string.format('Reply %s is-at %s', self.sip, self.sha)
            end
        end
        return ''
    end,
    ['ICMP'] = function(self)
        local typ = self.type
        local fields = {}

        if typ == socket.ICMP_ECHO or typ == socket.ICMP_ECHOREPLY then
            fields[#fields + 1] = typ == socket.ICMP_ECHO and 'ECHO' or 'ECHOREPLY'
            fields[#fields + 1] = 'seq ' .. self.sequence
            fields[#fields + 1] = 'id ' .. self.id
        else
            fields[#fields + 1] = 'type ' .. typ
        end

        fields[#fields + 1] = 'len ' .. #self.data

        return table.concat(fields, ' ')
    end,
    ['ICMPV6'] = function(self)
        local typ = self.type
        local fields = {}

        if typ == socket.ICMPV6_ECHO_REQUEST or typ == socket.ICMPV6_ECHO_REPLY then
            fields[#fields + 1] = typ == socket.ICMPV6_ECHO_REQUEST and 'ECHO' or 'ECHOREPLY'
            fields[#fields + 1] = 'seq ' .. self.sequence
            fields[#fields + 1] = 'id ' .. self.id
        else
            fields[#fields + 1] = 'type ' .. typ
        end

        fields[#fields + 1] = 'len ' .. #self.data

        return table.concat(fields, ' ')
    end,
    ['IP'] = function(self)
        local protocol = self.protocol
        local p = protocols[protocol]
        return self.saddr .. '->' .. self.daddr .. ' ' .. (p and p.name or protocol)
    end,
    ['IPV6'] = function(self)
        return self.saddr .. '->' .. self.daddr
    end,
    ['TCP'] = function(self)
        local tokens = {self.source .. '->' .. self.dest, 'len ' .. #self.data}

        for _, flag in ipairs({ 'syn', 'ack', 'rst', 'fin' }) do
            if self[flag] then
                tokens[#tokens + 1] = flag:upper()
            end
        end

        return table.concat(tokens, ' ')
    end,
    ['UDP'] = function(self)
        return self.source .. '->' .. self.dest .. ' len ' .. #self.data
    end
}

function mtable_decap:__tostring()
    if tostrings[self.name] then
        return tostrings[self.name](self)
    end
    return ''
end

--- Decoded packet object returned by parser helpers.
--
-- Common fields:
--
-- - `name`: protocol name, for example `"ETHER"`, `"IP"`, `"TCP"`.
-- - `proto` (optional): next L3 ethertype, usually present on L2 packets.
-- - `protocol` (optional): next L4 protocol number, usually present on IP packets.
-- - `data` (optional): remaining payload bytes.
-- - `source` (optional): source address or source port depending on packet layer.
-- - `dest` (optional): destination address or destination port depending on packet layer.
--
-- @type ParsedPacket

--- Decode the next protocol layer from current packet payload.
--
-- @function ParsedPacket:next
-- @treturn ParsedPacket next_pkt Decoded upper-layer packet.
-- @treturn[2] nil On failure.
-- @treturn[2] string err Error message.
function methods_decap:next()
    local data = self.data

    local proto = self.proto
    if proto then
        if not protos[proto] then
            return nil, 'unknown L3 proto "' .. proto .. '"'
        end
        return protos[proto].next(data)
    end

    local protocol = self.protocol
    if protocol then
        if not protocols[protocol] then
            return nil, 'unknown L4 protocol "' .. protocol .. '"'
        end
        return protocols[protocol].next(data, self)
    end

    return nil, 'no upper protocol layer'
end

--- End of `ParsedPacket` type section.
-- @section end

--- Decode a raw ICMP packet.
-- @function from_icmp
-- @tparam string data Raw ICMP bytes.
-- @treturn ParsedPacket Decoded ICMP packet.
-- @treturn[2] nil On failure.
-- @treturn[2] string err Error message.
function M.from_icmp(data)
    return protocols[socket.IPPROTO_ICMP].next(data)
end

--- Decode a raw ICMPv6 packet.
-- @function from_icmp6
-- @tparam string data Raw ICMPv6 bytes.
-- @treturn ParsedPacket Decoded ICMPv6 packet.
-- @treturn[2] nil On failure.
-- @treturn[2] string err Error message.
function M.from_icmp6(data)
    return protocols[socket.IPPROTO_ICMPV6].next(data)
end

--- Decode a raw IPv4 packet.
-- @function from_ip
-- @tparam string data Raw IPv4 bytes.
-- @treturn ParsedPacket Decoded IPv4 packet.
-- @treturn[2] nil On failure.
-- @treturn[2] string err Error message.
function M.from_ip(data)
    return protos[socket.ETH_P_IP].next(data)
end

--- Decode a raw IPv6 packet.
-- @function from_ip6
-- @tparam string data Raw IPv6 bytes.
-- @treturn ParsedPacket Decoded IPv6 packet.
-- @treturn[2] nil On failure.
-- @treturn[2] string err Error message.
function M.from_ip6(data)
    return protos[socket.ETH_P_IPV6].next(data)
end

--- Decode an Ethernet frame.
-- @function from_ether
-- @tparam string data Raw Ethernet frame bytes.
-- @treturn ParsedPacket Decoded Ethernet packet.
-- @treturn[2] nil On failure.
-- @treturn[2] string err Error message.
function M.from_ether(data)
    assert(type(data) == 'string')

    if #data < 14 then
        return nil, 'not a valid ether packet'
    end

    local dest = hex.encode(data:sub(1, 6), ':')
    local source = hex.encode(data:sub(7, 12), ':')
    local proto = string.unpack('>I2', data:sub(13))

    return setmetatable({
        name = 'ETHER',
        dest = dest,
        source = source,
        proto = proto,
        data = data:sub(15)
    }, mtable_decap)
end

local function parse_80211_ie(pkt, data)
    while #data >= 2 and #data - 2 >= data:byte(2) do
        local ie_type = data:byte(1)
        local ie_len = data:byte(2)

        data = data:sub(3)

        if ie_type == 0 then
            pkt.ssid = data:sub(1, ie_len)
        end

        data = data:sub(ie_len + 1)
    end
end

--- Decode an IEEE 802.11 frame from a radiotap packet.
--
-- This parser extracts commonly used management/data fields and selected
-- information elements (for example SSID in beacon/probe frames).
--
-- @function from_radiotap
-- @tparam string data Raw radiotap packet bytes.
-- @treturn ParsedPacket Decoded 802.11 packet.
-- @treturn[2] nil On failure.
-- @treturn[2] string err Error message.
function M.from_radiotap(data)
    assert(type(data) == 'string')

    if #data < 14 then
        return nil, 'not a valid radiotap packet'
    end

    local header_len = string.unpack('<I2', data:sub(3))

    data = data:sub(header_len + 1)

    local fc = string.unpack('<I2', data:sub(1))

    local typ = (fc >> 2) & 0x3
    local subtype = (fc >> 4) & 0xf

    local pkt = {
        name = '80211',
        version = fc & 0x3,
        type = typ,
        subtype = subtype,
        to_ds = (fc >> 8) & 01 == 1,
        from_ds = (fc >> 9) & 0x1 == 1,
        more_frag = (fc >> 10) & 0x1 == 1,
        retry = (fc >> 11) & 0x1 == 1,
        pwr_mgmt = (fc >> 12) & 0x1 == 1,
        more_data = (fc >> 13) & 0x1 == 1,
        protected  = (fc >> 14) & 0x1 == 1,
        plus_htc = (fc >> 15) & 0x1 == 1,
        duration = string.unpack('<I2', data:sub(3)),
        addr1 = hex.encode(data:sub(5, 10), ':')
    }

    if typ == nl80211.FTYPE_MGMT then
        pkt.addr2 = hex.encode(data:sub(11, 16), ':')
        pkt.addr3 = hex.encode(data:sub(17, 22), ':')

        data = data:sub(pkt.plus_htc and 29 or 25)

        if subtype == nl80211.STYPE_BEACON or subtype == nl80211.STYPE_PROBE_RESP then
            pkt.timestamp = string.unpack('<I8', data:sub(1))
            pkt.beacon_interval = string.unpack('<I2', data:sub(9))
            pkt.capability = string.unpack('<I2', data:sub(11))

            parse_80211_ie(pkt, data:sub(13))
        elseif subtype == nl80211.STYPE_PROBE_REQ then
            parse_80211_ie(pkt, data)
        end
    elseif typ == nl80211.FTYPE_DATA then
        pkt.addr2 = hex.encode(data:sub(11, 16), ':')
        pkt.addr3 = hex.encode(data:sub(17, 22), ':')

        if pkt.from_ds and pkt.to_ds then
            pkt.addr4 = hex.encode(data:sub(23, 28), ':')
        end
    end

    return setmetatable(pkt, mtable_decap)
end

local function csum_icmp(data)
    local count = #data
    local sum = 0
    local i = 1

    while i < count do
        sum = sum + data:byte(i) * 256 + data:byte(i + 1)
        i = i + 2
    end

    if i == count then
        sum = sum + data:byte(i) * 256
    end

    sum = (sum >> 16) + (sum & 0xffff)
    sum = sum + (sum >> 16)

    return ~sum & 0xffff
end

--- Build an ICMP echo or echo-reply packet.
--
-- `typ` must be one of `socket.ICMP_ECHO` or `socket.ICMP_ECHOREPLY`.
--
-- @function icmp
-- @tparam number typ ICMP type.
-- @tparam number code ICMP code.
-- @tparam number id Identifier.
-- @tparam number sequence Sequence number.
-- @tparam[opt=""] string data Payload.
-- @tparam[opt=false] boolean checksum Whether to compute and fill checksum.
-- @treturn string Raw ICMP packet bytes.
function M.icmp(typ, code, id, sequence, data, checksum)
    assert(typ == socket.ICMP_ECHO or typ == socket.ICMP_ECHOREPLY)

    data = data or ''

    local check = 0

    local buf = {
        string.char(typ, code),
        string.pack('>I2', check),
        string.pack('>I2', id),
        string.pack('>I2', sequence),
        data
    }

    if checksum then
        check = csum_icmp(table.concat(buf))
        buf[2] = string.pack('>I2', check)
    end

    return table.concat(buf)
end

--- Build an ICMPv6 echo request or echo reply packet.
--
-- `typ` must be one of `socket.ICMPV6_ECHO_REQUEST` or
-- `socket.ICMPV6_ECHO_REPLY`.
--
-- @function icmp6
-- @tparam number typ ICMPv6 type.
-- @tparam number code ICMPv6 code.
-- @tparam number id Identifier.
-- @tparam number sequence Sequence number.
-- @tparam[opt=""] string data Payload.
-- @tparam[opt=false] boolean checksum Whether to compute and fill checksum.
-- @treturn string Raw ICMPv6 packet bytes.
function M.icmp6(typ, code, id, sequence, data, checksum)
    assert(typ == socket.ICMPV6_ECHO_REQUEST or typ == socket.ICMPV6_ECHO_REPLY)

    data = data or ''

    local check = 0

    local buf = {
        string.char(typ, code),
        string.pack('>I2', check),
        string.pack('>I2', id),
        string.pack('>I2', sequence),
        data
    }

    if checksum then
        check = csum_icmp(table.concat(buf))
        buf[2] = string.pack('>I2', check)
    end

    return table.concat(buf)
end

local function csum_tcpudp(saddr, daddr, protocol, pkt)
    local function sum16bits(data)
        local sum = 0

        for i = 1, #data, 2 do
            if i + 1 <= #data then
                sum = sum + (data:byte(i) * 256 + data:byte(i + 1))
            else
                sum = sum + (data:byte(i) * 256)
            end

            if sum > 0xffff then
                sum = (sum & 0xffff) + (sum >> 16)
            end
        end

        return sum
    end

    local pseudo_header = table.concat({
        string.pack('I4', socket.inet_aton(saddr)),
        string.pack('I4', socket.inet_aton(daddr)),
        '\0',
        string.char(protocol),
        string.pack(">I2", #pkt)
    })

    local sum = sum16bits(pseudo_header) + sum16bits(pkt)

    while sum > 0xffff do
        sum = (sum & 0xffff) + (sum >> 16)
    end

    return ~sum & 0xffff
end

--- Build a UDP packet.
--
-- If both `saddr` and `daddr` are provided, UDP checksum is computed with an
-- IPv4 pseudo-header.
--
-- @function udp
-- @tparam number source Source port.
-- @tparam number dest Destination port.
-- @tparam[opt=""] string data UDP payload.
-- @tparam[opt] string saddr IPv4 source address used for checksum.
-- @tparam[opt] string daddr IPv4 destination address used for checksum.
-- @treturn string Raw UDP packet bytes.
function M.udp(source, dest, data, saddr, daddr)
    data = data or ''

    local len = 8 + #data
    local check = 0

    local buf = {
        string.pack('>I2', source),
        string.pack('>I2', dest),
        string.pack('>I2', len),
        string.pack('>I2', check),
        data
    }

    if saddr and daddr then
        check = csum_tcpudp(saddr, daddr, socket.IPPROTO_UDP, table.concat(buf))
        buf[4] = string.pack('>I2', check)
    end

    return table.concat(buf)
end

--- Build a TCP packet (without options).
--
-- The header length is fixed to 20 bytes (`doff = 5`), i.e. TCP options are
-- not included.
--
-- @function tcp
-- @tparam number source Source port.
-- @tparam number dest Destination port.
-- @tparam number seq Sequence number.
-- @tparam number ack_seq Acknowledgment number.
-- @tparam[opt] table flags TCP flags table.
-- @tparam[opt=false] boolean flags.cwr Congestion Window Reduced.
-- @tparam[opt=false] boolean flags.ece ECN-Echo.
-- @tparam[opt=false] boolean flags.urg Urgent pointer significant.
-- @tparam[opt=false] boolean flags.ack Acknowledgment valid.
-- @tparam[opt=false] boolean flags.psh Push function.
-- @tparam[opt=false] boolean flags.rst Reset connection.
-- @tparam[opt=false] boolean flags.syn Synchronize sequence numbers.
-- @tparam[opt=false] boolean flags.fin No more data from sender.
-- @tparam number window Window size.
-- @tparam string saddr IPv4 source address used for checksum.
-- @tparam string daddr IPv4 destination address used for checksum.
-- @tparam[opt=""] string data TCP payload.
-- @treturn string Raw TCP packet bytes.
function M.tcp(source, dest, seq, ack_seq, flags, window, saddr, daddr, data)
    flags = flags or {}
    data = data or ''

    local hl = 5
    local check = 0
    local flag = 0
    local urg_ptr = 0

    flag = flag | (flags.cwr and (1 << 7) or 0)
    flag = flag | (flags.ece and (1 << 6) or 0)
    flag = flag | (flags.urg and (1 << 5) or 0)
    flag = flag | (flags.ack and (1 << 4) or 0)
    flag = flag | (flags.psh and (1 << 3) or 0)
    flag = flag | (flags.rst and (1 << 2) or 0)
    flag = flag | (flags.syn and (1 << 1) or 0)
    flag = flag | (flags.fin and (1 << 0) or 0)

    local buf = {
        string.pack('>I2', source),
        string.pack('>I2', dest),
        string.pack('>I4', seq),
        string.pack('>I4', ack_seq),
        string.char(hl << 4, flag),
        string.pack('>I2', window),
        string.pack('>I2', check),
        string.pack('>I2', urg_ptr),
        data
    }

    check = csum_tcpudp(saddr, daddr, socket.IPPROTO_TCP, table.concat(buf))

    buf[7] = string.pack('>I2', check)

    return table.concat(buf)
end

--- Build an IPv4 packet.
--
-- This creates a minimal IPv4 header (no options) and computes header
-- checksum automatically.
--
-- @function ip
-- @tparam string saddr Source IPv4 address.
-- @tparam string daddr Destination IPv4 address.
-- @tparam number protocol IP protocol number, e.g. `socket.IPPROTO_UDP`.
-- @tparam[opt=""] string data IPv4 payload.
-- @treturn string Raw IPv4 packet bytes.
function M.ip(saddr, daddr, protocol, data)
    data = data or ''

    local version = 4
    local ihl = 5
    local tos = 0
    local tot_len = ihl * 4 + #data
    local id = 0
    local frag_off = 0
    local ttl = 64
    local check = 0

    local header = {
        string.char(version << 4 | ihl, tos),
        string.pack('>I2', tot_len),
        string.pack('>I2', id),
        string.pack('>I2', frag_off),
        string.char(ttl, protocol),
        string.pack('>I2', check),
        string.pack('I4', socket.inet_aton(saddr)),
        string.pack('I4', socket.inet_aton(daddr))
    }

    local buf = table.concat(header)

    for i = 1, #buf, 2 do
        check = check + (buf:byte(i) << 8) + buf:byte(i + 1)
        if check > 0xffff then
            check = (check & 0xffff) + (check >> 16)
        end
    end

    check = ~check & 0xffff

    header[6] = string.pack('>I2', check)

    return table.concat(header) .. data
end

--- Build an ARP packet.
--
-- Common operations are `socket.ARPOP_REQUEST` and `socket.ARPOP_REPLY`.
--
-- @function arp
-- @tparam number op ARP operation.
-- @tparam[opt="00:00:00:00:00:00"] string sha Sender MAC address.
-- @tparam[opt="0.0.0.0"] string sip Sender IPv4 address.
-- @tparam[opt="00:00:00:00:00:00"] string tha Target MAC address.
-- @tparam[opt="0.0.0.0"] string tip Target IPv4 address.
-- @treturn string Raw ARP packet bytes.
function M.arp(op, sha, sip, tha, tip)
    sha = sha or '00:00:00:00:00:00'
    sip = sip or '0.0.0.0'
    tha = tha or '00:00:00:00:00:00'
    tip = tip or '0.0.0.0'

    local buf = {
        string.pack('>I2', socket.ARPHRD_ETHER),
        string.pack('>I2', socket.ETH_P_IP),
        string.char(6, 4), -- hardware address length and proto address length
        string.pack('>I2', op),
        hex.decode(sha:gsub(':', '')),
        string.pack('I4', socket.inet_aton(sip)),
        hex.decode(tha:gsub(':', '')),
        string.pack('I4', socket.inet_aton(tip))
    }

    return table.concat(buf)
end

--- Build an Ethernet frame.
-- @function ether
-- @tparam string source Source MAC address, format `xx:xx:xx:xx:xx:xx`.
-- @tparam string dest Destination MAC address, format `xx:xx:xx:xx:xx:xx`.
-- @tparam number proto EtherType, e.g. `socket.ETH_P_IP`.
-- @tparam[opt=""] string data Ethernet payload.
-- @treturn string Raw Ethernet frame bytes.
function M.ether(source, dest, proto, data)
    data = data or ''

    local buf = {
        hex.decode(dest:gsub(':', '')),
        hex.decode(source:gsub(':', '')),
        string.pack('>I2', proto),
        data
    }

    return table.concat(buf)
end

return M
