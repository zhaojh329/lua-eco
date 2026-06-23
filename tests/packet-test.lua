#!/usr/bin/env eco

local PACKET_PATH = 'packet.lua'

do
    local f = io.open(PACKET_PATH)
    if f then
        f:close()
    else
        PACKET_PATH = '../packet.lua'
    end
end

local packet = dofile(PACKET_PATH)
local nl80211 = require 'eco.nl80211'
local socket = require 'eco.socket'

local saddr = '192.0.2.1'
local daddr = '198.51.100.2'
local payload = 'hello'
local udp = packet.udp(1234, 5678, payload, saddr, daddr)
local ip = packet.ip(saddr, daddr, socket.IPPROTO_UDP, udp)

local parsed = assert(packet.from_ip(ip))
assert(parsed.saddr == saddr, parsed.saddr)
assert(parsed.daddr == daddr, parsed.daddr)
assert(parsed.protocol == socket.IPPROTO_UDP)

local udp_parsed = assert(parsed:next())
assert(udp_parsed.source == 1234)
assert(udp_parsed.dest == 5678)
assert(udp_parsed.data == payload)

local eth = packet.ether('02:00:00:00:00:01', '02:00:00:00:00:02', socket.ETH_P_IP, ip)
local l2 = assert(packet.from_ether(eth))
local l3 = assert(l2:next())

assert(l3.saddr == saddr, l3.saddr)
assert(l3.daddr == daddr, l3.daddr)

local function mac(a, b, c, d, e, f)
    return string.char(a, b, c, d, e, f)
end

local function radiotap(frame, header_len)
    header_len = header_len or 8
    return string.char(0, 0) ..
           string.pack('<I2', header_len) ..
           string.pack('<I4', 0) ..
           string.rep('\0', header_len - 8) ..
           frame
end

local function fc(typ, subtype, flags)
    return (subtype << 4) | (typ << 2) | (flags or 0)
end

local function frame_header(frame_control)
    return string.pack('<I2', frame_control) ..
           string.pack('<I2', 0) ..
           mac(0x00, 0x11, 0x22, 0x33, 0x44, 0x55) ..
           mac(0x66, 0x77, 0x88, 0x99, 0xaa, 0xbb) ..
           mac(0xcc, 0xdd, 0xee, 0xff, 0x00, 0x11) ..
           string.pack('<I2', 0)
end

local function expect_bad_radiotap(data)
    local pkt, err = packet.from_radiotap(data)
    assert(pkt == nil)
    assert(err == 'not a valid radiotap packet', tostring(err))
end

expect_bad_radiotap(string.rep('\0', 7))
expect_bad_radiotap(string.char(0, 0) .. string.pack('<I2', 4) .. string.pack('<I4', 0))
expect_bad_radiotap(string.char(0, 0) .. string.pack('<I2', 12) .. string.pack('<I4', 0))
expect_bad_radiotap(radiotap('', 12))
expect_bad_radiotap(radiotap(string.pack('<I2', fc(nl80211.FTYPE_MGMT, nl80211.STYPE_PROBE_REQ))))
expect_bad_radiotap(radiotap(frame_header(fc(nl80211.FTYPE_MGMT, nl80211.STYPE_BEACON)):sub(1, 23)))
expect_bad_radiotap(radiotap(frame_header(fc(nl80211.FTYPE_MGMT, nl80211.STYPE_BEACON)) ..
                             string.rep('\0', 11)))
expect_bad_radiotap(radiotap(frame_header(fc(nl80211.FTYPE_DATA, nl80211.STYPE_DATA)):sub(1, 23)))
expect_bad_radiotap(radiotap(frame_header(fc(nl80211.FTYPE_DATA, nl80211.STYPE_DATA,
                                               (1 << 8) | (1 << 9)))))
expect_bad_radiotap(radiotap(frame_header(fc(nl80211.FTYPE_CTL, nl80211.STYPE_RTS)):sub(1, 10)))

local beacon = assert(packet.from_radiotap(
    radiotap(frame_header(fc(nl80211.FTYPE_MGMT, nl80211.STYPE_BEACON)) ..
             string.pack('<I8', 0) ..
             string.pack('<I2', 100) ..
             string.pack('<I2', 0) ..
             string.char(0, 3) .. 'eco')))

assert(beacon.addr1 == '00:11:22:33:44:55', beacon.addr1)
assert(beacon.addr2 == '66:77:88:99:aa:bb', beacon.addr2)
assert(beacon.addr3 == 'cc:dd:ee:ff:00:11', beacon.addr3)
assert(beacon.ssid == 'eco', beacon.ssid)
assert(beacon.beacon_interval == 100)

print('packet tests passed')
