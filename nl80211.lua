-- SPDX-License-Identifier: MIT
-- Author: Jianhui Zhao <zhaojh329@gmail.com>

local nl80211 = require 'eco.core.nl80211'
local hex = require 'eco.encoding.hex'
local socket = require 'eco.socket'
local sys = require 'eco.core.sys'
local genl = require 'eco.genl'
local bit = require 'eco.bit'
local nl = require 'eco.nl'

local str_byte = string.byte
local lshift = bit.lshift

local M = {}

local iftypes = {
    [nl80211.IFTYPE_UNSPECIFIED] = 'unspecified',
    [nl80211.IFTYPE_ADHOC] = 'IBSS',
    [nl80211.IFTYPE_STATION] = 'managed',
    [nl80211.IFTYPE_AP] = 'AP',
    [nl80211.IFTYPE_AP_VLAN] = 'AP/VLAN',
    [nl80211.IFTYPE_WDS] = 'WDS',
    [nl80211.IFTYPE_MONITOR] = 'monitor',
    [nl80211.IFTYPE_MESH_POINT] = 'mesh point"',
    [nl80211.IFTYPE_P2P_CLIENT] = 'P2P-client',
    [nl80211.IFTYPE_P2P_GO] = 'P2P-GO',
    [nl80211.IFTYPE_P2P_DEVICE] = 'P2P-device',
    [nl80211.IFTYPE_OCB] = 'outside context of a BSS'
}

local width_name = {
    [nl80211.CHAN_WIDTH_20_NOHT] = '20 MHz (no HT)',
    [nl80211.CHAN_WIDTH_20] = '20 MHz',
    [nl80211.CHAN_WIDTH_40] = '40 MHz',
    [nl80211.CHAN_WIDTH_80] = '80 MHz',
    [nl80211.CHAN_WIDTH_80P80] = '80+80 MHz',
    [nl80211.CHAN_WIDTH_160] = '160 MHz'
}

local channel_type_name = {
    [nl80211.CHAN_NO_HT] = 'NO HT',
    [nl80211.CHAN_HT20] = 'HT20',
    [nl80211.CHAN_HT40MINUS] = 'HT40-',
    [nl80211.CHAN_HT40PLUS] = 'HT40+'
}

function M.escape_ssid(ssid)
    local i = 0

    if not ssid then
        return ''
    end

    ssid = ssid:gsub('.', function(c)
        local n = str_byte(c)
        i = i + 1

        if n >= 33 and n <= 126 and c ~= ' ' and c ~= '\\' then
            return c
        elseif c == ' ' and i ~= 1 and i ~= #ssid then
            return ' '
        else
            return '\\x' .. string.format('%.2x', n)
        end
    end)

    return ssid
end

function M.iftype_name(iftype)
    return iftypes[iftype] or 'Unknown'
end

function M.width_name(width)
    return width_name[width] or 'Unknown'
end

function M.channel_type_name(typ)
    return channel_type_name[typ] or 'Unknown'
end

function M.freq_to_channel(freq)
    -- see 802.11-2007 17.3.8.3.2 and Annex J
    if freq == 2484 then
        return 14
    elseif freq < 2484 then
        return (freq - 2407) / 5
    elseif freq >= 4910 and freq <= 4980 then
        return (freq - 4000) / 5
    elseif freq <= 45000 then -- DMG band lower limit
        return (freq - 5000) / 5
    elseif freq >= 58320 and freq <= 64800 then
        return (freq - 56160) / 2160
    else
        return 0
    end
end

function M.freq_to_band(freq)
	if freq >= 2412 and freq <= 2484 then
		return 2.4
	elseif freq >= 5160 and freq <= 5885 then
		return 5
	elseif freq >= 5925 and freq <= 7125 then
		return 6
	elseif freq >= 58320 and freq <= 69120 then
		return 60
    end

	return 'Unknown'
end

local function prepare_send_cmd(cmd, flags)
    local nl80211_id, err = genl.get_family_id('nl80211')
    if not nl80211_id then
        return nil, err
    end

    local msg = nl.nlmsg(nl80211_id, bit.bor(nl.NLM_F_REQUEST, flags or 0))

    msg:put(genl.genlmsghdr({ cmd = cmd }))

    local sock, err = nl.open(nl.NETLINK_GENERIC)
    if not sock then
        return nil, err
    end

    return sock, msg
end

local function parse_interface(msg)
    local attrs = msg:parse_attr(genl.GENLMSGHDR_SIZE)
    local info = {}

    info.phy = nl.attr_get_u32(attrs[nl80211.ATTR_WIPHY])
    info.iftype = nl.attr_get_u32(attrs[nl80211.ATTR_IFTYPE])
    info.ifname = nl.attr_get_str(attrs[nl80211.ATTR_IFNAME])
    info.ifindex = nl.attr_get_u32(attrs[nl80211.ATTR_IFINDEX])
    info.wdev = nl.attr_get_u64(attrs[nl80211.ATTR_WDEV])
    info.use_4addr = nl.attr_get_u8(attrs[nl80211.ATTR_4ADDR]) == 1

    local mac = nl.attr_get_payload(attrs[nl80211.ATTR_MAC])
    info.mac = hex.encode(mac, ':')

    if attrs[nl80211.ATTR_SSID] then
        info.ssid = nl.attr_get_payload(attrs[nl80211.ATTR_SSID])
    end

    if attrs[nl80211.ATTR_WIPHY_FREQ] then
        info.freq = nl.attr_get_u32(attrs[nl80211.ATTR_WIPHY_FREQ])

        if attrs[nl80211.ATTR_CHANNEL_WIDTH] then
            info.channel_width = nl.attr_get_u32(attrs[nl80211.ATTR_CHANNEL_WIDTH])

            if attrs[nl80211.ATTR_CENTER_FREQ1] then
                info.center_freq1 = nl.attr_get_u32(attrs[nl80211.ATTR_CENTER_FREQ1])
            end

            if attrs[nl80211.ATTR_CENTER_FREQ2] then
                info.center_freq2 = nl.attr_get_u32(attrs[nl80211.ATTR_CENTER_FREQ2])
            end
        elseif attrs[nl80211.ATTR_WIPHY_CHANNEL_TYPE] then
            info.channel_type = nl.attr_get_u32(attrs[nl80211.ATTR_WIPHY_CHANNEL_TYPE])
        end
    end

    if attrs[nl80211.ATTR_WIPHY_TX_POWER_LEVEL] then
        info.txpower = nl.attr_get_u32(attrs[nl80211.ATTR_WIPHY_TX_POWER_LEVEL])
    end

    return info
end

function M.get_interface(ifname)
    if type(ifname) ~= 'string' then
        error('invalid ifname')
    end

    local ifidx = socket.if_nametoindex(ifname)
    if not ifidx then
        return nil, 'no dev'
    end

    local sock, msg = prepare_send_cmd(nl80211.CMD_GET_INTERFACE)
    if not sock then
        return nil, msg
    end

    msg:put_attr_u32(nl80211.ATTR_IFINDEX, ifidx)

    local ok, err = sock:send(msg)
    if not ok then
        return nil, err
    end

    msg, err = sock:recv()
    if not msg then
        return nil, err
    end

    local nlh = msg:next()
    if not nlh then
        return nil, 'no msg responsed'
    end

    if nlh.type == nl.NLMSG_ERROR then
        err = msg:parse_error()
        return nil, sys.strerror(-err)
    end

    return parse_interface(msg)
end

function M.get_interfaces(phy)
    local sock, msg = prepare_send_cmd(nl80211.CMD_GET_INTERFACE, nl.NLM_F_DUMP)
    if not sock then
        return nil, msg
    end

    if phy and type(phy) ~= 'number' then
        error('invalid phy index')
    end

    if phy then
        msg:put_attr_u32(nl80211.ATTR_WIPHY, phy)
    end

    local ok, err = sock:send(msg)
    if not ok then
        return nil, err
    end

    local interfaces = {}

    while true do
        msg, err = sock:recv()
        if not msg then
            return nil, err
        end

        while true do
            local nlh = msg:next()
            if not nlh then
                break
            end

            if nlh.type == nl.NLMSG_ERROR then
                err = msg:parse_error()
                return nil, sys.strerror(-err)
            end

            if nlh.type == nl.NLMSG_DONE then
                return interfaces
            end

            interfaces[#interfaces + 1] = parse_interface(msg)
        end
    end
end

local cipher_names = {
    [0] = 'NONE',
    [1] = 'WEP-40',
    [2] = 'TKIP',
    [4] = 'CCMP',
    [5] = 'WEP-104',
    [6] = 'AES-128-CMAC',
    [7] = 'NO-GROUP',
    [8] = 'GCMP',
    [9] = 'GCMP-256',
    [10] = 'CCMP-256'
}

local auth_suite_names = {
    [1] = '802.1X',
    [2] = 'PSK',
    [3] = 'FT/802.1X',
    [4] = 'FT/PSK',
    [5] = '802.1X/SHA-256',
    [6] = 'PSK/SHA-256',
    [7] = 'TDLS/TPK',
    [8] = 'SAE',
    [9] = 'FT/SAE',
    [11] = '802.1X/SUITE-B',
    [12] = '802.1X/SUITE-B-192',
    [13] = 'FT/802.1X/SHA-384',
    [14] = 'FILS/SHA-256',
    [15] = 'FILS/SHA-384',
    [16] = 'FT/FILS/SHA-256',
    [17] = 'FT/FILS/SHA-384',
    [18] = 'OWE'
}

local ms_oui        = string.char(0x00, 0x50, 0xf2)
local ieee80211_oui = string.char(0x00, 0x0f, 0xac)

local function parse_cipher(data)
    local id = str_byte(data, 4)

    if data:sub(1, 3) == ms_oui then
        if id < 6 then
            return cipher_names[id]
        end
    elseif data:sub(1, 3) == ieee80211_oui then
        if id < 11 then
            return cipher_names[id]
        end
    end

    return id
end

local function parse_rsn(data, defcipher, defauth)
    local res = {
        version = bit.bor(str_byte(data, 1),  lshift(str_byte(data, 2), 8)),
        group_cipher = defcipher,
        pair_ciphers = {},
        auth_suites = {}
    }

    local pair_ciphers = res.pair_ciphers
    local auth_suites = res.auth_suites

    data = data:sub(3)
    if #data < 4 then
        pair_ciphers[defcipher] = true
        return res
    end

    res.group_cipher = parse_cipher(data)

    data = data:sub(5)
    if #data < 2 then
        pair_ciphers[defcipher] = true
        return res
    end

    local count = bit.bor(str_byte(data, 1),  lshift(str_byte(data, 2), 8))
    if 2 + count * 4 > #data then
        pair_ciphers[defcipher] = true
        return res
    end

    data = data:sub(3)

    while count > 0 do
        pair_ciphers[parse_cipher(data)] = true
        count = count - 1
        data = data:sub(5)
    end

    if #data < 2 then
        auth_suites[defauth] = true
        return res
    end

    count = bit.bor(str_byte(data, 1),  lshift(str_byte(data, 2), 8))
    if 2 + count * 4 > #data then
        auth_suites[defauth] = true
        return res
    end

    data = data:sub(3)

    while count > 0 do
        local id = str_byte(data, 4)

        if data:sub(1, 3) == ms_oui then
            if id < 3 then
                auth_suites[auth_suite_names[id]] = true
            end
        elseif data:sub(1, 3) == ieee80211_oui then
            if id < 19 then
                auth_suites[auth_suite_names[id]] = true
            end
        end

        count = count - 1
        data = data:sub(5)
    end

    return res
end

local function parse_bss_ie(info, data)
    while #data >= 2 and #data - 2 >= str_byte(data, 2) do
        local typ = str_byte(data, 1)
        local ie_len = str_byte(data, 2)

        data = data:sub(3)

        -- SSID or Mesh ID
        if typ == 0 or typ == 114 then
            info.ssid = data:sub(1, ie_len)
        elseif typ == 48 then -- RSN
            info.rsn = parse_rsn(data:sub(1, ie_len), 'CCMP', '8021x')
        elseif typ == 221 then   -- Vendor
            if ie_len >= 4 and data:sub(1, 3) == ms_oui then
                if str_byte(data, 4) == 1 then
                    info.wpa = parse_rsn(data:sub(5, ie_len), 'TKIP', 'PSK')
                end
            end
        end

        data = data:sub(ie_len + 1)
    end
end

local function parse_bss(nest)
    local attrs = nl.parse_attr_nested(nest)
    local info = { caps = {} }

    if not attrs[nl80211.BSS_BSSID] or not attrs[nl80211.BSS_CAPABILITY] then
        return nil
    end

    local caps = nl.attr_get_u16(attrs[nl80211.BSS_CAPABILITY])

    if bit.band(caps, lshift(1, 0)) > 0 then
        info.caps['ESS'] = true
    end

    if bit.band(caps, lshift(1, 1)) > 0 then
        info.cap['IBSS'] = true
    end

    if bit.band(caps, lshift(1, 4)) > 0 then
        info.caps['PRIVACY'] = true
    end

    local bssid = nl.attr_get_payload(attrs[nl80211.BSS_BSSID])
    info.bssid = hex.encode(bssid, ':')

    info.freq = nl.attr_get_u32(attrs[nl80211.BSS_FREQUENCY])
    info.channel = M.freq_to_channel(info.freq)
    info.band = M.freq_to_band(info.freq)

    if attrs[nl80211.BSS_BEACON_INTERVAL] then
        info.beacon_interval = nl.attr_get_u16(attrs[nl80211.BSS_BEACON_INTERVAL])
    end

    if attrs[nl80211.BSS_SIGNAL_MBM] then
         info.signal = nl.attr_get_s32(attrs[nl80211.BSS_SIGNAL_MBM]) / 100.0
    end

    if attrs[nl80211.BSS_INFORMATION_ELEMENTS] then
        parse_bss_ie(info, nl.attr_get_payload(attrs[nl80211.BSS_INFORMATION_ELEMENTS]))
    end

    return info
end

function M.scan(action, params)
    local flags = 0
    local cmd

    if action == 'trigger' then
        flags = nl.NLM_F_ACK
        cmd = nl80211.CMD_TRIGGER_SCAN
    elseif action == 'dump' then
        flags = nl.NLM_F_DUMP
        cmd = nl80211.CMD_GET_SCAN
    elseif action == 'abort' then
        flags = nl.NLM_F_ACK
        cmd = nl80211.CMD_ABORT_SCAN
    else
        error('invalid scan action')
    end

    params = params or {}

    if type(params.ifname) ~= 'string' then
        error('invalid ifname')
    end

    local ifidx = socket.if_nametoindex(params.ifname)
    if not ifidx then
        return nil, 'no such device'
    end

    local sock, msg = prepare_send_cmd(cmd, flags)
    if not sock then
        return nil, msg
    end

    msg:put_attr_u32(nl80211.ATTR_IFINDEX, ifidx)

    if action == 'trigger' then
        local ssids = params.ssids

        if type(ssids) ~= 'table' or #ssids == 0 then
            ssids = { '' }
        end

        msg:put_attr_nest_start(nl80211.ATTR_SCAN_SSIDS)
        for i, ssid in ipairs(ssids) do
            msg:put_attr_str(i, ssid)
        end
        msg:put_attr_nest_end()

        local freqs = params.freqs
        if type(freqs) == 'table' and #freqs > 0 then
            msg:put_attr_nest_start(nl80211.ATTR_SCAN_FREQUENCIES)
            for i, freq in ipairs(freqs) do
                msg:put_attr_u32(i, freq)
            end
            msg:put_attr_nest_end()
        end
    end

    local ok, err = sock:send(msg)
    if not ok then
        return nil, err
    end

    if cmd ~= nl80211.CMD_GET_SCAN then
        msg, err = sock:recv()
        if not msg then
            return nil, err
        end

        local nlh = msg:next()
        if not nlh then
            return nil, 'no msg responsed'
        end

        if nlh.type ~= nl.NLMSG_ERROR then
            return nil, 'invalid msg received'
        end

        local err = msg:parse_error()
        if err ~= 0 then
            return nil, sys.strerror(-err)
        end

        return true
    end

    local bss = {}

    while true do
        msg, err = sock:recv()
        if not msg then
            return nil, err
        end

        while true do
            local nlh = msg:next()
            if not nlh then
                break
            end

            if nlh.type == nl.NLMSG_ERROR then
                err = msg:parse_error()
                return nil, sys.strerror(-err)
            end

            if nlh.type == nl.NLMSG_DONE then
                return bss
            end

            local attrs = msg:parse_attr(genl.GENLMSGHDR_SIZE)
            if attrs[nl80211.ATTR_BSS] then
                local res = parse_bss(attrs[nl80211.ATTR_BSS])
                if res then
                    bss[#bss + 1] = res
                end
            end
        end
    end
end

--[[
    The callback function "cb" must return a boolean value to stop waiting event.
    Return true or return false following a error message.
    The callback will get three params: cmd, attrs, data.
--]]
function M.wait_event(grp_name, timeout, cb, data)
    local grp = genl.get_group_id('nl80211', grp_name)
    if not grp then
        return nil, 'not support'
    end

    local sock, err = nl.open(nl.NETLINK_GENERIC)
    if not sock then
        return nil, err
    end

    local ok, err = sock:bind(0)
    if not ok then
        return nil, err
    end

    sock:add_membership(grp)

    local deadtime

    if timeout then
        deadtime = sys.uptime() + timeout
    end

    while true do
        local msg, err = sock:recv(nil, deadtime and (deadtime - sys.uptime()))
        if not msg then
            return nil, err
        end

        local nlh = msg:next()
        if not nlh then
            return nil, 'invalid msg received'
        end

        if nlh.type == nl.NLMSG_ERROR then
            err = msg:parse_error()
            return nil, sys.strerror(-err)
        end

        local hdr = genl.parse_genlmsghdr(msg)
        local attrs = msg:parse_attr(genl.GENLMSGHDR_SIZE)

        ok, err = cb(hdr.cmd, attrs, data)
        if ok == true then
            return true
        elseif ok == false then
            return false, err
        end
    end
end

local function parse_bitrate(attrs)
    local r = {}
    local rate = 0
    local mcs

    if attrs[nl80211.RATE_INFO_BITRATE32] then
        rate = nl.attr_get_u32(attrs[nl80211.RATE_INFO_BITRATE32])
    elseif attrs[nl80211.RATE_INFO_BITRATE] then
        rate = nl.attr_get_u16(attrs[nl80211.RATE_INFO_BITRATE32])
    end

    r.rate = rate / 10

    if attrs[nl80211.RATE_INFO_EHT_MCS] then
        r.eht = true

        mcs = nl.attr_get_u8(attrs[nl80211.RATE_INFO_EHT_MCS])

        if attrs[nl80211.RATE_INFO_EHT_NSS] then
            r.nss = nl.attr_get_u8(attrs[nl80211.RATE_INFO_EHT_NSS])
        end

        if attrs[nl80211.RATE_INFO_EHT_GI] then
            r.eht_gi = nl.attr_get_u8(attrs[nl80211.RATE_INFO_EHT_GI])
        end
    elseif attrs[nl80211.RATE_INFO_HE_MCS] then
        r.he = true

        mcs = nl.attr_get_u8(attrs[nl80211.RATE_INFO_HE_MCS])

        if attrs[nl80211.RATE_INFO_HE_NSS] then
            r.nss = nl.attr_get_u8(attrs[nl80211.RATE_INFO_HE_NSS])
        end

        if attrs[nl80211.RATE_INFO_HE_GI] then
            r.he_gi = nl.attr_get_u8(attrs[nl80211.RATE_INFO_HE_GI])
        end

        if attrs[nl80211.RATE_INFO_HE_RU_ALLOC] then
            r.he_ru_alloc = nl.attr_get_u8(attrs[nl80211.RATE_INFO_HE_RU_ALLOC])
        end

        if attrs[nl80211.RATE_INFO_HE_DCM] then
            r.he_dcm = nl.attr_get_u8(attrs[nl80211.RATE_INFO_HE_DCM])
        end
    elseif attrs[nl80211.RATE_INFO_VHT_MCS] then
        r.vht = true

        mcs = nl.attr_get_u8(attrs[nl80211.RATE_INFO_VHT_MCS])

        if attrs[nl80211.RATE_INFO_VHT_NSS] then
            r.nss = nl.attr_get_u8(attrs[nl80211.RATE_INFO_VHT_NSS])
        end
    elseif attrs[nl80211.RATE_INFO_MCS] then
        mcs = nl.attr_get_u8(attrs[nl80211.RATE_INFO_MCS])
    end

    r.mcs = mcs

    if attrs[nl80211.RATE_INFO_5_MHZ_WIDTH] then
        r.width = 5
    elseif attrs[nl80211.RATE_INFO_10_MHZ_WIDTH] then
        r.width = 10
    elseif attrs[nl80211.RATE_INFO_40_MHZ_WIDTH] then
        r.width = 40
    elseif attrs[nl80211.RATE_INFO_80_MHZ_WIDTH] then
        r.width = 80
    elseif attrs[nl80211.RATE_INFO_80P80_MHZ_WIDTH] or attrs[nl80211.RATE_INFO_160_MHZ_WIDTH] then
        r.width = 160
    else
        r.width = 20
    end

    if attrs[nl80211.RATE_INFO_SHORT_GI] then
        r.short_gi = true
    end

    return r
end

local function parse_station(attrs, sinfo)
    local info = {}

    local mac = nl.attr_get_payload(attrs[nl80211.ATTR_MAC])
    info.mac = hex.encode(mac, ':')

    if sinfo[nl80211.STA_INFO_INACTIVE_TIME] then
        info.inactive_time = nl.attr_get_u32(sinfo[nl80211.STA_INFO_INACTIVE_TIME])
    end

    if sinfo[nl80211.STA_INFO_CONNECTED_TIME] then
        info.connected_time = nl.attr_get_u32(sinfo[nl80211.STA_INFO_CONNECTED_TIME])
    end

    if sinfo[nl80211.STA_INFO_BEACON_LOSS] then
        info.beacon_loss = nl.attr_get_u32(sinfo[nl80211.STA_INFO_BEACON_LOSS])
    end

    if sinfo[nl80211.STA_INFO_BEACON_RX] then
        info.beacon_rx = nl.attr_get_u64(sinfo[nl80211.STA_INFO_BEACON_RX])
    end

    if sinfo[nl80211.STA_INFO_RX_BYTES64] then
        info.rx_bytes = nl.attr_get_u64(sinfo[nl80211.STA_INFO_RX_BYTES64])
    elseif sinfo[nl80211.STA_INFO_RX_BYTES] then
        info.rx_bytes = nl.attr_get_u32(sinfo[nl80211.STA_INFO_RX_BYTES])
    end

    if sinfo[nl80211.STA_INFO_TX_BYTES64] then
        info.tx_bytes = nl.attr_get_u64(sinfo[nl80211.STA_INFO_TX_BYTES64])
    elseif sinfo[nl80211.STA_INFO_TX_BYTES] then
        info.tx_bytes = nl.attr_get_u32(sinfo[nl80211.STA_INFO_TX_BYTES])
    end

    if sinfo[nl80211.STA_INFO_RX_PACKETS] then
        info.rx_packets = nl.attr_get_u32(sinfo[nl80211.STA_INFO_RX_PACKETS])
    end

    if sinfo[nl80211.STA_INFO_TX_PACKETS] then
        info.tx_packets = nl.attr_get_u32(sinfo[nl80211.STA_INFO_TX_PACKETS])
    end

    if sinfo[nl80211.STA_INFO_TX_RETRIES] then
        info.tx_retries = nl.attr_get_u32(sinfo[nl80211.STA_INFO_TX_RETRIES])
    end

    if sinfo[nl80211.STA_INFO_TX_FAILED] then
        info.tx_failed = nl.attr_get_u32(sinfo[nl80211.STA_INFO_TX_FAILED])
    end

    if sinfo[nl80211.STA_INFO_SIGNAL] then
        info.signal = nl.attr_get_s8(sinfo[nl80211.STA_INFO_SIGNAL])
    end

    if sinfo[nl80211.STA_INFO_SIGNAL_AVG] then
        info.signal_avg = nl.attr_get_s8(sinfo[nl80211.STA_INFO_SIGNAL_AVG])
    end

    if sinfo[nl80211.STA_INFO_BEACON_SIGNAL_AVG] then
        info.beacon_signal_avg = nl.attr_get_s8(sinfo[nl80211.STA_INFO_BEACON_SIGNAL_AVG])
    end

    if sinfo[nl80211.STA_INFO_ACK_SIGNAL] then
        info.ack_signal = nl.attr_get_s8(sinfo[nl80211.STA_INFO_ACK_SIGNAL])
    end

    if sinfo[nl80211.STA_INFO_ACK_SIGNAL_AVG] then
        info.ack_signal_avg = nl.attr_get_s8(sinfo[nl80211.STA_INFO_ACK_SIGNAL_AVG])
    end

    if sinfo[nl80211.STA_INFO_STA_FLAGS] then
        local flags = nl80211.parse_sta_flag_update(nl.attr_get_payload(sinfo[nl80211.STA_INFO_STA_FLAGS]))
        for k, v in pairs(flags) do
            info[k] = v
        end
    end

    if sinfo[nl80211.STA_INFO_RX_BITRATE] then
        info.rx_rate = parse_bitrate(nl.parse_attr_nested(sinfo[nl80211.STA_INFO_RX_BITRATE]))
    end

    if sinfo[nl80211.STA_INFO_TX_BITRATE] then
        info.tx_rate = parse_bitrate(nl.parse_attr_nested(sinfo[nl80211.STA_INFO_TX_BITRATE]))
    end

    return info
end

function M.get_station(ifname, mac)
    if type(ifname) ~= 'string' then
        error('invalid ifname')
    end

    if type(mac) ~= 'string' then
        error('invalid mac')
    end

    local ifidx = socket.if_nametoindex(ifname)
    if not ifidx then
        return nil, 'no dev'
    end

    local sock, msg = prepare_send_cmd(nl80211.CMD_GET_STATION)
    if not sock then
        return nil, msg
    end

    msg:put_attr_u32(nl80211.ATTR_IFINDEX, ifidx)
    msg:put_attr(nl80211.ATTR_MAC, hex.decode(mac:gsub(':', '')))

    local ok, err = sock:send(msg)
    if not ok then
        return nil, err
    end

    msg, err = sock:recv()
    if not msg then
        return nil, err
    end

    local nlh = msg:next()
    if not nlh then
        return nil, 'no msg responsed'
    end

    if nlh.type == nl.NLMSG_ERROR then
        err = msg:parse_error()
        return nil, sys.strerror(-err)
    end

    local attrs = msg:parse_attr(genl.GENLMSGHDR_SIZE)
    if not attrs[nl80211.ATTR_STA_INFO] then
        return nil, 'invalid received'
    end

    local sinfo = nl.parse_attr_nested(attrs[nl80211.ATTR_STA_INFO])
    return parse_station(attrs, sinfo)
end

function M.get_stations(ifname)
    if type(ifname) ~= 'string' then
        error('invalid ifname')
    end

    local ifidx = socket.if_nametoindex(ifname)
    if not ifidx then
        return nil, 'no dev'
    end

    local sock, msg = prepare_send_cmd(nl80211.CMD_GET_STATION, nl.NLM_F_DUMP)
    if not sock then
        return nil, msg
    end

    msg:put_attr_u32(nl80211.ATTR_IFINDEX, ifidx)

    local ok, err = sock:send(msg)
    if not ok then
        return nil, err
    end

    local stations = {}

    while true do
        msg, err = sock:recv()
        if not msg then
            return nil, err
        end

        while true do
            local nlh = msg:next()
            if not nlh then
                break
            end

            if nlh.type == nl.NLMSG_ERROR then
                err = msg:parse_error()
                return nil, sys.strerror(-err)
            end

            if nlh.type == nl.NLMSG_DONE then
                return stations
            end

            local attrs = msg:parse_attr(genl.GENLMSGHDR_SIZE)
            if attrs[nl80211.ATTR_STA_INFO] then
                local sinfo = nl.parse_attr_nested(attrs[nl80211.ATTR_STA_INFO])
                local res = parse_station(attrs, sinfo)
                if res then
                    stations[#stations + 1] = res
                end
            end
        end
    end
end

return setmetatable(M, { __index = nl80211 })
