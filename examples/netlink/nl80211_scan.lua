#!/usr/bin/env eco

local nl80211 = require 'eco.nl80211'
local network = require 'eco.network'
local nl = require 'eco.nl'

local ifname = 'wlan0'

local ok, err = nl80211.scan('trigger', { ifname = ifname, ssids = { '', 'test1', 'test2' }, freqs = { 2412, 2417 } })
if not ok then
    print(err)
    return
end

local ifindex = network.if_nametoindex(ifname)

ok, err = nl80211.wait_event('scan', 15.0, function(cmd, attrs)
    if cmd == nl80211.CMD_SCAN_ABORTED or cmd == nl80211.CMD_NEW_SCAN_RESULTS then
        if nl.attr_get_u32(attrs[nl80211.ATTR_IFINDEX]) == ifindex then
            if cmd == nl80211.CMD_SCAN_ABORTED then
                return false, 'aborted'
            end

            if cmd == nl80211.CMD_NEW_SCAN_RESULTS then
                return true
            end
        end
    end
end)
if not ok then
    print(err)
    return
end

local res, err = nl80211.scan('dump', { ifname = ifname })
if not res then
    print(err)
    return
end

local function print_field(k, v, intend)
    intend = intend or 0
    for i = 1, intend do
        io.write('    ')
    end

    print(k .. ': ' .. v)
end

local function print_rsn(rsn)
    print_field('Version', rsn.version, 1)
    print_field('Group cipher', rsn.group_cipher, 1)
    print_field('Pairwise ciphers', table.concat(table.keys(rsn.pair_ciphers), ' '), 1)
    print_field('Authentication suites', table.concat(table.keys(rsn.auth_suites), ' '), 1)
end

for _, bss in ipairs(res) do
    print_field('BSSID', bss.bssid)
    print_field('SSID', nl80211.escape_ssid(bss.ssid))
    print_field('capability', table.concat(table.keys(bss.caps), ' '))
    print_field('Frequency', bss.freq / 1000 .. ' GHz')
    print_field('Band', bss.band .. ' GHz')
    print_field('Channel', bss.channel)

    if bss.rsn then
        print('RSN:')
        print_rsn(bss.rsn)
    end

    if bss.wpa then
        print('WPA:')
        print_rsn(bss.wpa)
    end

    print()
end
