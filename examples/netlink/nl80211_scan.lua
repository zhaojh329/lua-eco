#!/usr/bin/env eco

local nl80211 = require 'eco.nl80211'

local ifname = 'wlan0'

local ok, err = nl80211.scan('trigger', { ifname = ifname, ssids = { '', 'test1', 'test2' }, freqs = { 2412, 2417 } })
if not ok then
    print(err)
    return
end

ok, err = nl80211.wait_scan_done(ifname, 15.0)
if not ok then
    print(err)
    return
end

local res, err = nl80211.scan('dump', { ifname = ifname })
if not res then
    print(err)
    return
end

local function print_rsn(rsn)
    print('', 'Version:', rsn.version)
    print('', 'Group cipher:', rsn.group_cipher)
    print('', 'Pairwise ciphers:', table.concat(rsn.pair_ciphers, ' '))
    print('', 'Authentication suites:', table.concat(rsn.auth_suites, ' '))
end

for _, bss in ipairs(res) do
    print('BSSID:', bss.bssid)
    print('SSID:', nl80211.escape_ssid(bss.ssid))
    print('Mode:', bss.mode)
    print('Frequency:', bss.freq / 1000 .. ' GHz')
    print('Band:', bss.band .. ' GHz')
    print('Channel:', bss.channel)

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
