#!/usr/bin/env eco

local nl80211 = require 'eco.nl80211'

local ok, err = nl80211.set_interface('wlan-test0', {
    ['4addr'] = true
})
if not ok then
    print(err)
end
