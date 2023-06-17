#!/usr/bin/env eco

local nl80211 = require 'eco.nl80211'

local info, err = nl80211.get_station('wlan0', '0e:a8:9c:eb:da:30')
if not info then
    print(err)
    return
end

for k, v in pairs(info) do
    print(k .. ':', v)
end
