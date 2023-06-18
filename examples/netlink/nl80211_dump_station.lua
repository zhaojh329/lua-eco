#!/usr/bin/env eco

local nl80211 = require 'eco.nl80211'

local function format_rate(r)
    local s = {}

    s[#s + 1] = r.rate .. ' MBit/s'
    s[#s + 1] = r.width .. 'MHz'

    if r.eht then
        s[#s + 1] = 'EHT-MCS ' .. r.mcs
        s[#s + 1] = 'EHT-NSS ' .. r.nss
        s[#s + 1] = 'EHT-GI ' .. r.he_gi
    elseif r.he then
        s[#s + 1] = 'HE-MCS ' .. r.mcs
        s[#s + 1] = 'HE-NSS ' .. r.nss
        s[#s + 1] = 'HE-GI ' .. r.he_gi
        s[#s + 1] = 'HE-DCM ' .. r.he_dcm
    elseif r.vht then
        s[#s + 1] = 'VHT-MCS ' .. r.mcs
        if r.nss then
            s[#s + 1] = 'VHT-NSS ' .. r.nss
        end
    elseif r.mcs then
        s[#s + 1] = 'MCS ' .. r.mcs
    end

    if r.short_gi then
        s[#s + 1] = 'short GI'
    end

    return table.concat(s, ', ')
end

local function print_sta(sta)
    print('mac:', sta.mac)
    print('inactive time:', sta.inactive_time .. ' ms')
    print('rx bytes:', sta.rx_bytes)
    print('rx packets:', sta.rx_packets)
    print('tx bytes:', sta.tx_bytes)
    print('tx packets:', sta.tx_packets)
    print('tx retries:', sta.tx_retries)
    print('tx failed:', sta.tx_failed)
    print('signal:', sta.signal .. ' dBm')
    print('signal avg:', sta.signal_avg .. ' dBm')
    print('avg ack signal:', sta.ack_signal_avg .. ' dBm')
    print('tx bitrate:', format_rate(sta.tx_rate))
    print('rx bitrate:', format_rate(sta.rx_rate))
    print('authorized:', sta.authorized)
    print('authenticated:', sta.authenticated)
    print('associated:', sta.associated)
    print('preamble:', sta.preamble)
    print('WMM/WME:', sta.wme)
    print('MFP:', sta.mfp)

    if sta.beacon_loss then
        print('beacon loss:', sta.beacon_loss)
    end

    if sta.beacon_rx then
        print('beacon interval:', sta.beacon_rx)
    end

    print('connected time:', sta.connected_time .. ' seconds')
end

local stations, err = nl80211.get_stations('wlan0')
if not stations then
    print(err)
    return
end

for _, sta in ipairs(stations) do
    print_sta(sta)
    print()
end
