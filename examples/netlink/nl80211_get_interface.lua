#!/usr/bin/env eco

local nl80211 = require 'eco.nl80211'

local info, err = nl80211.get_interface('wlan0')
if not info then
    print(err)
    return
end

print('phy:', info.phy)
print('ifname:', info.ifname)
print('ifindex:', info.ifindex)
print('wdev:', string.format('0x%x', info.wdev))
print('mac:', info.mac)
print('use_4addr:', info.use_4addr)

if info.ssid then
    print('ssid:', nl80211.escape_ssid(info.ssid))
end

print('type:', nl80211.iftype_name(info.iftype))

if info.freq then
    local chan_info = string.format('%d (%d MHz)', nl80211.freq_to_channel(info.freq), info.freq)

    if info.channel_width then
        chan_info = chan_info .. ', width: ' .. nl80211.width_name(info.channel_width)

        if info.center_freq1 then
            chan_info = chan_info .. ', center1: ' .. string.format('%d MHz', info.center_freq1)
        end

        if info.center_freq2 then
            chan_info = chan_info .. ', center2: ' .. string.format('%d MHz', info.center_freq2)
        end
    elseif info.channel_type then
        chan_info = chan_info .. ' ' .. nl80211.channel_type_name(info.channel_type)
    end

    print('channel:', chan_info)
end

if info.txpower then
    print('txpower:', string.format('%d.%.2d dBm', info.txpower / 100, info.txpower % 100))
end
