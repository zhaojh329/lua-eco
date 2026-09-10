#!/usr/bin/env eco

local nl = require 'eco.nl'
local nl80211 = require 'eco.nl80211'
local test = require 'test'

local OUI_IEEE80211 = string.char(0x00, 0x0f, 0xac)
local OUI_MICROSOFT = string.char(0x00, 0x50, 0xf2)

local function get_upvalue(fn, target)
    local index = 1

    while true do
        local name, value = debug.getupvalue(fn, index)
        if not name then
            error('upvalue not found: ' .. target)
        end

        if name == target then
            return value
        end

        index = index + 1
    end
end

local function suite(oui, id)
    return oui .. string.char(id)
end

local function rsn(oui, auth_suite)
    return string.pack('<I2', 1) ..
           suite(oui, 4) ..
           string.pack('<I2', 1) .. suite(oui, 4) ..
           string.pack('<I2', 1) .. suite(oui, auth_suite)
end

local function ie(typ, data)
    return string.char(typ, #data) .. data
end

local function wpa_ie(auth_suite)
    local data = OUI_MICROSOFT .. string.char(1) ..
                 rsn(OUI_MICROSOFT, auth_suite)

    return ie(nl80211.WLAN_EID_VENDOR_SPECIFIC, data)
end

local nl80211_scan = get_upvalue(nl80211.scan, 'nl80211_scan')
local parse_bss = get_upvalue(nl80211_scan, 'parse_bss')

local function parse_bss_info(information_ies, beacon_ies, keep_elems)
    local msg = nl.nlmsg(0, 0)

    msg:put_attr_nest_start(1)
    msg:put_attr(nl80211.BSS_BSSID, string.rep('\0', 6))
    msg:put_attr(nl80211.BSS_CAPABILITY, string.pack('=I2', 1))
    msg:put_attr_u32(nl80211.BSS_FREQUENCY, 2412)

    if information_ies then
        msg:put_attr(nl80211.BSS_INFORMATION_ELEMENTS, information_ies)
    end

    if beacon_ies then
        msg:put_attr(nl80211.BSS_BEACON_IES, beacon_ies)
    end

    msg:put_attr_nest_end()

    local rx = nl.nlmsg_ker(msg:binary())
    assert(rx:next())

    local attrs, err = rx:parse_attr(0)
    assert(attrs, err)

    return assert(parse_bss(attrs[1], keep_elems))
end

test.run_case_sync('beacon IEs fill missing RSN and WPA data', function()
    local beacon_ies = ie(nl80211.WLAN_EID_RSN, rsn(OUI_IEEE80211, 6)) ..
                       wpa_ie(2)
    local info = parse_bss_info(nil, beacon_ies)

    assert(info.rsn.auth_suites['PSK/SHA-256'])
    assert(info.wpa.auth_suites.PSK)
end)

test.run_case_sync('beacon IEs do not replace primary data', function()
    local primary_ies = ie(nl80211.WLAN_EID_SSID, 'probe') ..
                        ie(nl80211.WLAN_EID_RSN, rsn(OUI_IEEE80211, 2)) ..
                        wpa_ie(2)
    local beacon_ies = ie(nl80211.WLAN_EID_SSID, 'beacon') ..
                       ie(nl80211.WLAN_EID_RSN, rsn(OUI_IEEE80211, 6)) ..
                       wpa_ie(1)
    local info = parse_bss_info(primary_ies, beacon_ies, true)

    assert(info.ssid == 'probe')
    assert(info.rsn.auth_suites.PSK)
    assert(not info.rsn.auth_suites['PSK/SHA-256'])
    assert(info.wpa.auth_suites.PSK)
    assert(not info.wpa.auth_suites['802.1X'])
    assert(info.elems[nl80211.WLAN_EID_SSID][1] == 'probe')
end)

test.run_case_sync('malformed security IEs are ignored', function()
    local malformed_wpa = OUI_MICROSOFT .. string.char(1)
    local primary_ies = ie(nl80211.WLAN_EID_RSN, '') ..
                        ie(nl80211.WLAN_EID_RSN, string.char(1)) ..
                        ie(nl80211.WLAN_EID_VENDOR_SPECIFIC, malformed_wpa) ..
                        ie(nl80211.WLAN_EID_VENDOR_SPECIFIC, malformed_wpa .. string.char(1))
    local beacon_ies = ie(nl80211.WLAN_EID_RSN, rsn(OUI_IEEE80211, 6))
    local info = parse_bss_info(primary_ies, beacon_ies)

    assert(info.rsn.auth_suites['PSK/SHA-256'])
    assert(info.wpa == nil)
end)

print('nl80211 tests passed')
