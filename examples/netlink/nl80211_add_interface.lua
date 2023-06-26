#!/usr/bin/env eco

local nl80211 = require 'eco.nl80211'

local ok, err = nl80211.add_interface('phy0', 'wlan-test0', {
    type = nl80211.IFTYPE_STATION,
    mac = '00:15:5d:41:a1:4b'
})
if not ok then
    print(err)
end
