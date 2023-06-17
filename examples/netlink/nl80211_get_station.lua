#!/usr/bin/env eco

local nl80211 = require 'eco.nl80211'

local stations, err = nl80211.get_stations('wlan0')
if not stations then
    print(err)
    return
end

for _, sta in ipairs(stations) do
    for k, v in pairs(sta) do
        print(k .. ':', v)
    end
    print()
end
