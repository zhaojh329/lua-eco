-- SPDX-License-Identifier: MIT
-- Author: Jianhui Zhao <zhaojh329@gmail.com>

--- Linux nl80211 helpers.
--
-- This module is a convenience wrapper for the Linux `nl80211` Generic Netlink
-- family (Wi‑Fi configuration and status). It uses @{eco.genl} to resolve the
-- family and multicast group ids, and @{eco.nl} to send/receive netlink
-- messages.
--
-- Constants from Linux `NL80211_*` definitions are exported as:
--
-- - commands: `CMD_*`
-- - attributes: `ATTR_*`
-- - interface types: `IFTYPE_*`
-- - bands/channel widths/rate-info keys: `BAND_*`, `CHAN_*`, `CHAN_WIDTH_*`, `RATE_INFO_*`
-- - BSS/station/survey attribute keys: `BSS_*`, `STA_INFO_*`, `SURVEY_INFO_*`
--
-- In addition, this Lua module defines a few IEEE 802.11 constants
-- (`FTYPE_*`, `STYPE_*`, `WLAN_EID_*`) and helper functions for formatting and
-- parsing.
--
-- Most operations require sufficient privileges (typically `CAP_NET_ADMIN`).
--
-- @module eco.nl80211

local nl80211 = require 'eco.internal.nl80211'
local hex = require 'eco.encoding.hex'
local socket = require 'eco.socket'
local file = require 'eco.file'
local genl = require 'eco.genl'
local nl = require 'eco.nl'

local str_byte = string.byte

local M = {
    FTYPE_MGMT  = 0x00,
    FTYPE_CTL   = 0x01,
    FTYPE_DATA  = 0x02,
    FTYPE_EXT   = 0x11,

    -- management
    STYPE_ASSOC_REQ     = 0x00,
    STYPE_ASSOC_RESP    = 0x01,
    STYPE_REASSOC_REQ   = 0x02,
    STYPE_REASSOC_RESP  = 0x03,
    STYPE_PROBE_REQ     = 0x04,
    STYPE_PROBE_RESP    = 0x05,
    STYPE_BEACON        = 0x08,
    STYPE_ATIM          = 0x09,
    STYPE_DISASSOC      = 0x0a,
    STYPE_AUTH          = 0x0b,
    STYPE_DEAUTH        = 0x0c,
    STYPE_ACTION        = 0x0d,

    -- control
    STYPE_TRIGGER   = 0x02,
    STYPE_CTL_EXT   = 0x06,
    STYPE_BACK_REQ  = 0x08,
    STYPE_BACK      = 0x09,
    STYPE_PSPOLL    = 0x0a,
    STYPE_RTS       = 0x0b,
    STYPE_CTS       = 0x0c,
    STYPE_ACK       = 0x0d,
    STYPE_CFEND     = 0x0e,
    STYPE_CFENDACK  = 0x0f,

    -- data
    STYPE_DATA              = 0x00,
    STYPE_DATA_CFACK        = 0x01,
    STYPE_DATA_CFPOLL       = 0x02,
    STYPE_DATA_CFACKPOLL    = 0x03,
    STYPE_NULLFUNC          = 0x04,
    STYPE_CFACK             = 0x05,
    STYPE_CFPOLL            = 0x06,
    STYPE_CFACKPOLL         = 0x07,
    STYPE_QOS_DATA          = 0x08,
    STYPE_QOS_DATA_CFACK    = 0x09,
    STYPE_QOS_DATA_CFPOLL   = 0x0a,
    STYPE_QOS_DATA_CFACKPOLL= 0x0b,
    STYPE_QOS_NULLFUNC      = 0x0c,
    STYPE_QOS_CFACK         = 0x0d,
    STYPE_QOS_CFPOLL        = 0x0e,
    STYPE_QOS_CFACKPOLL     = 0x0f,

    -- Element IDs (IEEE Std 802.11-2020, 9.4.2.1, Table 9-92)
    WLAN_EID_SSID = 0,
    WLAN_EID_RSN = 48,
    WLAN_EID_MESH_ID = 114,
    WLAN_EID_VENDOR_SPECIFIC = 221,
}

--- Interface info returned by @{nl80211.get_interface} / @{nl80211.get_interfaces}.
-- @table interface
-- @field phy int PHY index.
-- @field iftype int Interface type (`IFTYPE_*`).
-- @field ifname string Interface name.
-- @field ifindex int Interface index.
-- @field wdev number Wireless device id.
-- @field mac string MAC address as "xx:xx:xx:xx:xx:xx".
-- @field ssid string|nil SSID (raw bytes) when available.
-- @field freq int|nil Frequency (MHz).
-- @field channel_width int|nil Channel width (`CHAN_WIDTH_*`).
-- @field channel_type int|nil Channel type (`CHAN_*`).
-- @field center_freq1 int|nil Center frequency 1.
-- @field center_freq2 int|nil Center frequency 2.
-- @field txpower int|nil TX power level.
-- @field 4addr boolean Whether 4-address mode is enabled.

--- @section end

--- BSS info returned by @{nl80211.scan} dump.
-- @table bss
-- @field bssid string BSSID as "xx:xx:..".
-- @field ssid string|nil SSID (raw bytes).
-- @field caps table Capability flags map.
-- @field freq int Frequency (MHz).
-- @field band number|string Band (2.4/5/6/60 or "Unknown").
-- @field channel int Channel number.
-- @field signal number|nil Signal strength (dBm).
-- @field beacon_interval int|nil Beacon interval.
-- @field rsn table|nil RSN information (parsed).
-- @field wpa table|nil WPA information (parsed).
-- @field status string|nil Link status: authenticated/associated/ibss_joined.
-- @field elems table|nil Raw parsed information elements (when keep_elems is true).

--- @section end

--- Survey info returned by @{nl80211.get_surveys}.
-- @table survey
-- @field frequency int|nil Frequency (MHz).
-- @field noise int|nil Noise (dBm).
-- @field in_use boolean|nil Whether currently in use.
-- @field active_time number|nil Active time.
-- @field busy_time number|nil Busy time.

--- @section end

--- Station info returned by @{nl80211.get_station} / @{nl80211.get_stations}.
-- @table station
-- @field mac string Station MAC address.
-- @field inactive_time int|nil
-- @field connected_time int|nil
-- @field beacon_loss int|nil
-- @field beacon_rx number|nil
-- @field rx_bytes number|nil
-- @field tx_bytes number|nil
-- @field rx_packets int|nil
-- @field tx_packets int|nil
-- @field tx_retries int|nil
-- @field tx_failed int|nil
-- @field signal int|nil
-- @field signal_avg int|nil
-- @field beacon_signal_avg int|nil
-- @field ack_signal int|nil
-- @field ack_signal_avg int|nil
-- @field noise int|nil
-- @field rx_rate table|nil Parsed bitrate table.
-- @field tx_rate table|nil Parsed bitrate table.
-- @field authorized boolean|nil
-- @field authenticated boolean|nil
-- @field associated boolean|nil
-- @field preamble string|nil "short" or "long".
-- @field wme boolean|nil
-- @field mfp boolean|nil

--- @section end

local ftypes = {
    [M.FTYPE_MGMT] = {
        [M.STYPE_ASSOC_REQ]     = 'ASSOC_REQ',
        [M.STYPE_ASSOC_RESP]    = 'ASSOC_RESP  ',
        [M.STYPE_REASSOC_REQ]   = 'REASSOC_REQ ',
        [M.STYPE_REASSOC_RESP]  = 'REASSOC_RESP',
        [M.STYPE_PROBE_REQ]     = 'PROBE_REQ',
        [M.STYPE_PROBE_RESP]    = 'PROBE_RESP',
        [M.STYPE_BEACON]        = 'BEACON',
        [M.STYPE_ATIM]          = 'ATIM',
        [M.STYPE_DISASSOC]      = 'DISASSOC',
        [M.STYPE_AUTH]          = 'AUTH',
        [M.STYPE_DEAUTH]        = 'DEAUTH',
        [M.STYPE_ACTION]        = 'ACTION'
    },
    [M.FTYPE_CTL] = {
        [M.STYPE_TRIGGER]  = 'TRIGGER',
        [M.STYPE_CTL_EXT]  = 'CTL_EXT',
        [M.STYPE_BACK_REQ] = 'BACK_REQ',
        [M.STYPE_BACK]     = 'BACK',
        [M.STYPE_PSPOLL]   = 'PSPOLL',
        [M.STYPE_RTS]      = 'RTS',
        [M.STYPE_CTS]      = 'CTS',
        [M.STYPE_ACK]      = 'ACK',
        [M.STYPE_CFEND]    = 'CFEND',
        [M.STYPE_CFENDACK] = 'CFENDACK'
    },
    [M.FTYPE_DATA] = {
        [M.STYPE_DATA]              = 'DATA',
        [M.STYPE_DATA_CFACK]        = 'DATA_CFACK',
        [M.STYPE_DATA_CFPOLL]       = 'DATA_CFPOLL',
        [M.STYPE_DATA_CFACKPOLL]    = 'DATA_CFACKPOLL',
        [M.STYPE_NULLFUNC]          = 'NULLFUNC',
        [M.STYPE_CFACK]             = 'CFACK',
        [M.STYPE_CFPOLL]            = 'CFPOLL',
        [M.STYPE_CFACKPOLL]         = 'CFACKPOLL',
        [M.STYPE_QOS_DATA]          = 'QOS_DATA',
        [M.STYPE_QOS_DATA_CFACK]    = 'QOS_DATA_CFACK',
        [M.STYPE_QOS_DATA_CFPOLL]   = 'QOS_DATA_CFPOLL',
        [M.STYPE_QOS_DATA_CFACKPOLL]= 'QOS_DATA_CFACKPOLL',
        [M.STYPE_QOS_NULLFUNC]      = 'QOS_NULLFUNC',
        [M.STYPE_QOS_CFACK]         = 'QOS_CFACK',
        [M.STYPE_QOS_CFPOLL]        = 'QOS_CFPOLL',
        [M.STYPE_QOS_CFACKPOLL]     = 'QOS_CFACKPOLL'
    }
}

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
    [nl80211.CHAN_WIDTH_160] = '160 MHz',
    [nl80211.CHAN_WIDTH_320] = '320 MHz'
}

local channel_type_name = {
    [nl80211.CHAN_NO_HT] = 'NO HT',
    [nl80211.CHAN_HT20] = 'HT20',
    [nl80211.CHAN_HT40MINUS] = 'HT40-',
    [nl80211.CHAN_HT40PLUS] = 'HT40+'
}

local OUI_MICROSOFT = '\x00\x50\xf2'
local OUI_IEEE80211 = '\x00\x0f\xac'

--- Get readable 802.11 frame type/subtype name.
--
-- @function ftype_name
-- @tparam int typ Frame type (one of `FTYPE_*`).
-- @tparam int subtype Frame subtype (one of `STYPE_*`).
-- @treturn string|nil name
function M.ftype_name(typ, subtype)
    return ftypes[typ] and ftypes[typ][subtype]
end

--- Escape SSID bytes for display.
--
-- Non-printable bytes are escaped as `\\xNN`.
--
-- @function escape_ssid
-- @tparam string|nil ssid Raw SSID bytes.
-- @treturn string escaped
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

--- Get readable interface type name.
--
-- @function iftype_name
-- @tparam int iftype Interface type (`IFTYPE_*`).
-- @treturn string name
function M.iftype_name(iftype)
    return iftypes[iftype] or 'Unknown'
end

--- Get readable channel width name.
--
-- @function width_name
-- @tparam int width Channel width (`CHAN_WIDTH_*`).
-- @treturn string name
function M.width_name(width)
    return width_name[width] or 'Unknown'
end

--- Get readable channel type name.
--
-- @function channel_type_name
-- @tparam int typ Channel type (`CHAN_*`).
-- @treturn string name
function M.channel_type_name(typ)
    return channel_type_name[typ] or 'Unknown'
end

--- Convert frequency (MHz) to channel number.
--
-- @function freq_to_channel
-- @tparam int freq Frequency in MHz.
-- @treturn int channel Channel number, or 0 if unknown.
function M.freq_to_channel(freq)
    if freq >= 2412 and freq <= 2484 then
        if freq == 2484 then
            return 14
        else
            return (freq - 2407) // 5
        end
    elseif freq >= 5180 and freq <= 5925 then
        return (freq - 5000) // 5
    elseif freq >= 5955 and freq <= 7115 then
        return (freq - 5950) // 5
    else
        return 0
    end
end

--- Convert frequency (MHz) to band.
--
-- @function freq_to_band
-- @tparam int freq Frequency in MHz.
-- @treturn number|string band One of 2.4, 5, 6, 60, or "Unknown".
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

    local msg = nl.nlmsg(nl80211_id, nl.NLM_F_REQUEST | (flags or 0))

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
    info['4addr'] = nl.attr_get_u8(attrs[nl80211.ATTR_4ADDR]) == 1

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

--- Resolve a PHY name (e.g. "phy0") to PHY index.
--
-- Reads `/sys/class/ieee80211/<name>/index`.
--
-- @function phy_lookup
-- @tparam string name PHY name.
-- @treturn int|nil phy PHY index.
function M.phy_lookup(name)
    local path = string.format('/sys/class/ieee80211/%s/index', name)
    return file.access(path) and file.readfile(path, '*n')
end

local function put_interface_attrs(msg, attrs)
    for k, v in pairs(attrs or {}) do
        if k == 'type' then
            msg:put_attr_u32(nl80211.ATTR_IFTYPE, v)
        elseif k == 'mac' then
            msg:put_attr(nl80211.ATTR_MAC, hex.decode(v:gsub(':', '')))
        elseif k == '4addr' then
            msg:put_attr_u8(nl80211.ATTR_4ADDR, v and 1 or 0)
        end
    end
end

--- Add a wireless interface.
--
-- `phy` may be a PHY name (string) or PHY index (number).
-- Supported `attrs` keys:
--
-- - `type` (int): interface type (`IFTYPE_*`)
-- - `mac` (string): MAC address as "xx:xx:.."
-- - `4addr` (boolean)
--
-- @function add_interface
-- @tparam string|int phy PHY name or index.
-- @tparam string ifname Interface name to create.
-- @tparam[opt] table attrs Optional attributes.
-- @treturn boolean true On success.
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
function M.add_interface(phy, ifname, attrs)
    local phyid

    if type(phy) == 'string' then
        phyid = M.phy_lookup(phy)
        if not phyid then
            return nil, string.format('"%s" not exists', phy)
        end
    elseif type(phy) == 'number' then
        phyid = phy
    else
        error('invalid phy')
    end

    if type(ifname) ~= 'string' then
        error('invalid ifname')
    end

    if socket.if_nametoindex(ifname) then
        return nil, string.format('"%s" already exists', ifname)
    end

    local sock<close>, msg = prepare_send_cmd(nl80211.CMD_NEW_INTERFACE, nl.NLM_F_ACK)
    if not sock then
        return nil, msg
    end

    attrs = attrs or {}

    msg:put_attr_u32(nl80211.ATTR_WIPHY, phyid)
    msg:put_attr_strz(nl80211.ATTR_IFNAME, ifname)

    put_interface_attrs(msg, attrs)

    return sock:request_ack(msg)
end

--- Set wireless interface attributes.
--
-- Uses the same `attrs` keys as @{add_interface}.
--
-- @function set_interface
-- @tparam string ifname Interface name.
-- @tparam[opt] table attrs Attributes.
-- @treturn boolean true On success.
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
function M.set_interface(ifname, attrs)
    if type(ifname) ~= 'string' then
        error('invalid ifname')
    end

    local if_index = socket.if_nametoindex(ifname)
    if not if_index then
        return nil, string.format('"%s" not exists', ifname)
    end

    local sock<close>, msg = prepare_send_cmd(nl80211.CMD_SET_INTERFACE, nl.NLM_F_ACK)
    if not sock then
        return nil, msg
    end

    msg:put_attr_u32(nl80211.ATTR_IFINDEX, if_index)

    put_interface_attrs(msg, attrs)

    return sock:request_ack(msg)
end

--- Delete a wireless interface.
--
-- @function del_interface
-- @tparam string ifname Interface name.
-- @treturn boolean true On success.
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
function M.del_interface(ifname)
    if type(ifname) ~= 'string' then
        error('invalid ifname')
    end

    local if_index = socket.if_nametoindex(ifname)
    if not if_index then
        return nil, string.format('"%s" not exists', ifname)
    end

    local sock<close>, msg = prepare_send_cmd(nl80211.CMD_DEL_INTERFACE, nl.NLM_F_ACK)
    if not sock then
        return nil, msg
    end

    msg:put_attr_u32(nl80211.ATTR_IFINDEX, if_index)

    return sock:request_ack(msg)
end

local function get_interface(sock, msg, ifidx)
    local info

    msg:put_attr_u32(nl80211.ATTR_IFINDEX, ifidx)

    local ok, err = sock:request_dump(msg, function(reply, nlh)
        if nlh.type < nl.NLMSG_MIN_TYPE then
            return
        end

        info = parse_interface(reply)
        return true
    end)
    if not ok then
        return nil, err
    end

    if not info then
        return nil, 'no msg responsed'
    end

    return info
end

--- Get interface info.
--
-- @function get_interface
-- @tparam string ifname Interface name.
-- @treturn interface info
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
function M.get_interface(ifname)
    if type(ifname) ~= 'string' then
        error('invalid ifname')
    end

    local ifidx = socket.if_nametoindex(ifname)
    if not ifidx then
        return nil, 'no dev'
    end

    local sock<close>, msg = prepare_send_cmd(nl80211.CMD_GET_INTERFACE)
    if not sock then
        return nil, msg
    end

    return get_interface(sock, msg, ifidx)
end

local function get_interfaces(sock, msg, phy)
    if phy and type(phy) ~= 'number' then
        error('invalid phy index')
    end

    if phy then
        msg:put_attr_u32(nl80211.ATTR_WIPHY, phy)
    end

    local interfaces = {}

    local ok, err = sock:request_dump(msg, function(reply, nlh)
        if nlh.type < nl.NLMSG_MIN_TYPE then
            return
        end

        interfaces[#interfaces + 1] = parse_interface(reply)
    end)
    if not ok then
        return nil, err
    end

    return interfaces
end

--- Dump interfaces.
--
-- If `phy` is provided, filters by PHY index.
--
-- @function get_interfaces
-- @tparam[opt] int phy PHY index.
-- @treturn table interfaces Array of @{interface}.
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
function M.get_interfaces(phy)
    local sock<close>, msg = prepare_send_cmd(nl80211.CMD_GET_INTERFACE, nl.NLM_F_DUMP)
    if not sock then
        return nil, msg
    end

    return get_interfaces(sock, msg, phy)
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

local function parse_cipher(data)
    local oui = data:sub(1, 3)
    local id = str_byte(data, 4)

    if oui == OUI_MICROSOFT then
        if id < 6 then
            return cipher_names[id]
        end
    elseif oui == OUI_IEEE80211 then
        if id < 11 then
            return cipher_names[id]
        end
    end

    return id
end

local function parse_rsn(data, defcipher, defauth)
    local res = {
        version = str_byte(data, 1) | str_byte(data, 2) << 8,
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

    local count = str_byte(data, 1) | str_byte(data, 2) << 8
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

    count = str_byte(data, 1) | str_byte(data, 2) << 8
    if 2 + count * 4 > #data then
        auth_suites[defauth] = true
        return res
    end

    data = data:sub(3)

    while count > 0 do
        local oui = data:sub(1, 3)
        local id = str_byte(data, 4)

        if oui == OUI_MICROSOFT then
            if id < 3 then
                auth_suites[auth_suite_names[id]] = true
            end
        elseif oui == OUI_IEEE80211 then
            if id < 19 then
                auth_suites[auth_suite_names[id]] = true
            end
        end

        count = count - 1
        data = data:sub(5)
    end

    return res
end

local function parse_vendor_specific_ie(info, data)
    if #data < 4 then
        return
    end

    local oui = data:sub(1, 3)
    local id = str_byte(data, 4)

    if oui == OUI_MICROSOFT then
        if id == 1 then
            info.wpa = parse_rsn(data:sub(5), 'TKIP', 'PSK')
        end
    end
end

local function parse_bss_ie(info, data, keep_elems)
    local elems = {}

    while #data > 1 do
        local typ, elem_data, i = string.unpack('Bs1', data)
        if not typ then
            break
        end

        if typ == M.WLAN_EID_SSID or typ == M.WLAN_EID_MESH_ID then
            info.ssid = elem_data
        elseif typ == M.WLAN_EID_RSN then
            info.rsn = parse_rsn(elem_data, 'CCMP', '8021x')
        elseif typ == M.WLAN_EID_VENDOR_SPECIFIC then
            parse_vendor_specific_ie(info, elem_data)
        end

        if keep_elems then
            if not elems[typ] then
                elems[typ] = {}
            end

            local elem = elems[typ]
            elem[#elem + 1] = elem_data
        end

        data = data:sub(i)
    end

    if keep_elems then
        info.elems = elems
    end
end

local function parse_bss(nest, keep_elems)
    local attrs = nl.parse_attr_nested(nest)
    local info = { caps = {} }

    if not attrs[nl80211.BSS_BSSID] or not attrs[nl80211.BSS_CAPABILITY] then
        return nil
    end

    local caps = nl.attr_get_u16(attrs[nl80211.BSS_CAPABILITY])

    if caps & 1 << 0 > 0 then
        info.caps['ESS'] = true
    end

    if caps & 1 << 1 > 0 then
        info.caps['IBSS'] = true
    end

    if caps & 1 << 4 > 0 then
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
        parse_bss_ie(info, nl.attr_get_payload(attrs[nl80211.BSS_INFORMATION_ELEMENTS]), keep_elems)
    end

    if attrs[nl80211.BSS_STATUS] then
        local status = nl.attr_get_u32(attrs[nl80211.BSS_STATUS])

        if status == nl80211.BSS_STATUS_AUTHENTICATED then
            info.status = 'authenticated'
        elseif status == nl80211.BSS_STATUS_ASSOCIATED then
            info.status = 'associated'
        elseif status == nl80211.BSS_STATUS_IBSS_JOINED then
            info.status = 'ibss_joined'
        end
    end

    return info
end

local function nl80211_scan(sock, msg, action, cmd, params)
    if type(params.ifname) ~= 'string' then
        error('invalid ifname')
    end

    local ifidx = socket.if_nametoindex(params.ifname)
    if not ifidx then
        return nil, 'no such device'
    end

    msg:put_attr_u32(nl80211.ATTR_IFINDEX, ifidx)

    if action == 'trigger' then
        local ssids = params.ssids
        if type(ssids) == 'table' and #ssids > 0 then
            msg:put_attr_nest_start(nl80211.ATTR_SCAN_SSIDS)
            for i, ssid in ipairs(ssids) do
                msg:put_attr_str(i, ssid)
            end
            msg:put_attr_nest_end()
        end

        local freqs = params.freqs
        if type(freqs) == 'table' and #freqs > 0 then
            msg:put_attr_nest_start(nl80211.ATTR_SCAN_FREQUENCIES)
            for i, freq in ipairs(freqs) do
                msg:put_attr_u32(i, freq)
            end
            msg:put_attr_nest_end()
        end

        if params.ie then
            msg:put_attr(nl80211.ATTR_IE, params.ie)
        end
    end

    if cmd ~= nl80211.CMD_GET_SCAN then
        return sock:request_ack(msg)
    end

    local bss = {}

    local ok, err = sock:request_dump(msg, function(reply, nlh)
        if nlh.type < nl.NLMSG_MIN_TYPE then
            return
        end

        local attrs = reply:parse_attr(genl.GENLMSGHDR_SIZE)
        if attrs[nl80211.ATTR_BSS] then
            local res = parse_bss(attrs[nl80211.ATTR_BSS], params.keep_elems)
            if res then
                bss[#bss + 1] = res
            end
        end
    end)
    if not ok then
        return nil, err
    end

    return bss
end

--- Scan operations.
--
-- - `action == 'trigger'`: trigger scan (ACK)
-- - `action == 'dump'`: dump scan results (returns array of @{bss})
-- - `action == 'abort'`: abort scan (ACK)
--
-- `params` fields:
--
-- - `ifname` (string, required)
-- - `ssids` (table, optional): list of SSIDs; pass `{''}` for wildcard
-- - `freqs` (table, optional): list of frequencies in MHz
-- - `ie` (string, optional): extra IEs
-- - `keep_elems` (boolean, optional): include raw `elems` in BSS results
--
-- @function scan
-- @tparam string action One of `trigger`, `dump`, `abort`.
-- @tparam table params Parameters.
-- @treturn boolean|table ok For `trigger/abort` returns `true`; for `dump` returns array of @{bss}.
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
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

    local sock<close>, msg = prepare_send_cmd(cmd, flags)
    if not sock then
        return nil, msg
    end

    return nl80211_scan(sock, msg, action, cmd, params)
end

local function wait_event(sock, grp_name, timeout, cb, data)
    local grp = genl.get_group_id('nl80211', grp_name)
    if not grp then
        return nil, 'not support'
    end

    local ok, err = sock:bind(0)
    if not ok then
        return nil, err
    end

    ok, err = sock:add_membership(grp)
    if not ok then
        return nil, err
    end

    return sock:recv_messages(function(msg, nlh)
        if nlh.type < nl.NLMSG_MIN_TYPE then
            return
        end

        local hdr = genl.parse_genlmsghdr(msg)
        local attrs = msg:parse_attr(genl.GENLMSGHDR_SIZE)

        ok, err = cb(hdr.cmd, attrs, data)
        if ok == true then
            return true
        elseif ok == false then
            return false, err
        end
    end, nil, nil, timeout)
end

--- Wait for a nl80211 multicast event.
--
-- Subscribes to the given multicast group and receives messages until the
-- callback stops the loop.
--
-- The callback `cb(cmd, attrs, data)` should return:
--
-- - `true` to stop and return success
-- - `false, err` to stop and return error
-- - `nil` to continue waiting
--
-- @function wait_event
-- @tparam string grp_name Multicast group name (e.g. `"scan"`).
-- @tparam number timeout Timeout in seconds for each receive.
-- @tparam function cb Callback.
-- @tparam[opt] any data User data passed to callback.
-- @treturn boolean true On success.
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
function M.wait_event(grp_name, timeout, cb, data)
    local sock<close>, err = nl.open(nl.NETLINK_GENERIC)
    if not sock then
        return nil, err
    end

    return wait_event(sock, grp_name, timeout, cb, data)
end

local function get_surveys(sock, msg, ifidx)
    msg:put_attr_u32(nl80211.ATTR_IFINDEX, ifidx)

    local surveys = {}


    local ok, err = sock:request_dump(msg, function(reply, nlh)
        if nlh.type < nl.NLMSG_MIN_TYPE then
            return
        end

        local attrs = reply:parse_attr(genl.GENLMSGHDR_SIZE)
        if attrs[nl80211.ATTR_SURVEY_INFO] then
            local si = nl.parse_attr_nested(attrs[nl80211.ATTR_SURVEY_INFO])
            local survey = {}

            if si[nl80211.SURVEY_INFO_FREQUENCY] then
                survey.frequency = nl.attr_get_u32(si[nl80211.SURVEY_INFO_FREQUENCY])
            end

            if si[nl80211.SURVEY_INFO_NOISE] then
                survey.noise = nl.attr_get_s8(si[nl80211.SURVEY_INFO_NOISE])
            end

            if si[nl80211.SURVEY_INFO_IN_USE] then
                survey.in_use = true
            end

            if si[nl80211.SURVEY_INFO_TIME] then
                survey.active_time = nl.attr_get_u64(si[nl80211.SURVEY_INFO_TIME])
            end

            if si[nl80211.SURVEY_INFO_TIME_BUSY] then
                survey.busy_time = nl.attr_get_u64(si[nl80211.SURVEY_INFO_TIME_BUSY])
            end

            surveys[#surveys + 1] = survey
        end
    end)
    if not ok then
        return nil, err
    end

    return surveys
end

--- Get survey information.
--
-- @function get_surveys
-- @tparam string ifname Interface name.
-- @treturn table surveys Array of @{survey}.
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
function M.get_surveys(ifname)
    if type(ifname) ~= 'string' then
        error('invalid ifname')
    end

    local ifidx = socket.if_nametoindex(ifname)
    if not ifidx then
        return nil, 'no dev'
    end

    local sock<close>, msg = prepare_send_cmd(nl80211.CMD_GET_SURVEY, nl.NLM_F_DUMP)
    if not sock then
        return nil, msg
    end

    return get_surveys(sock, msg, ifidx)
end

--- Get noise level (dBm).
--
-- Convenience wrapper over @{get_surveys}.
--
-- @function get_noise
-- @tparam string ifname Interface name.
-- @treturn int noise Noise in dBm (0 if not available).
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
function M.get_noise(ifname)
    local surveys, err = M.get_surveys(ifname)
    if not surveys then
        return nil, err
    end

    for _, survey in ipairs(surveys) do
        if survey.noise then
            return survey.noise
        end
    end

    return 0
end

local function parse_bitrate(attrs)
    local r = {}
    local rate = 0
    local mcs

    if attrs[nl80211.RATE_INFO_BITRATE32] then
        rate = nl.attr_get_u32(attrs[nl80211.RATE_INFO_BITRATE32])
    elseif attrs[nl80211.RATE_INFO_BITRATE] then
        rate = nl.attr_get_u16(attrs[nl80211.RATE_INFO_BITRATE])
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

local function get_station(sock, msg, ifname, mac)
    local ifidx = socket.if_nametoindex(ifname)
    if not ifidx then
        return nil, 'no dev'
    end

    msg:put_attr_u32(nl80211.ATTR_IFINDEX, ifidx)
    msg:put_attr(nl80211.ATTR_MAC, hex.decode(mac:gsub(':', '')))

    local res

    local ok, err = sock:request_dump(msg, function(reply, nlh)
        if nlh.type < nl.NLMSG_MIN_TYPE then
            return
        end

        local attrs = reply:parse_attr(genl.GENLMSGHDR_SIZE)
        if not attrs[nl80211.ATTR_STA_INFO] then
            return false, 'invalid received'
        end

        local sinfo = nl.parse_attr_nested(attrs[nl80211.ATTR_STA_INFO])

        res = parse_station(attrs, sinfo)
        res.noise = M.get_noise(ifname) or 0

        return true
    end)
    if not ok then
        return nil, err
    end

    if not res then
        return nil, 'no msg responsed'
    end

    return res
end

--- Get station info for a single peer.
--
-- @function get_station
-- @tparam string ifname Interface name.
-- @tparam string mac Station MAC address.
-- @treturn station info
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
function M.get_station(ifname, mac)
    if type(ifname) ~= 'string' then
        error('invalid ifname')
    end

    if type(mac) ~= 'string' then
        error('invalid mac')
    end

    local sock<close>, msg = prepare_send_cmd(nl80211.CMD_GET_STATION)
    if not sock then
        return nil, msg
    end

    return get_station(sock, msg, ifname, mac)
end

local function get_stations(sock, msg, ifname)
    local ifidx = socket.if_nametoindex(ifname)
    if not ifidx then
        return nil, 'no dev'
    end

    msg:put_attr_u32(nl80211.ATTR_IFINDEX, ifidx)

    local noise = M.get_noise(ifname) or 0

    local stations = {}

    local ok, err = sock:request_dump(msg, function(reply, nlh)
        if nlh.type < nl.NLMSG_MIN_TYPE then
            return
        end

        local attrs = reply:parse_attr(genl.GENLMSGHDR_SIZE)
        if attrs[nl80211.ATTR_STA_INFO] then
            local sinfo = nl.parse_attr_nested(attrs[nl80211.ATTR_STA_INFO])
            local res = parse_station(attrs, sinfo)
            if res then
                res.noise = noise
                stations[#stations + 1] = res
            end
        end
    end)
    if not ok then
        return nil, err
    end

    return stations
end

--- Dump stations on an interface.
--
-- @function get_stations
-- @tparam string ifname Interface name.
-- @treturn table stations Array of @{station}.
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
function M.get_stations(ifname)
    if type(ifname) ~= 'string' then
        error('invalid ifname')
    end

    local sock<close>, msg = prepare_send_cmd(nl80211.CMD_GET_STATION, nl.NLM_F_DUMP)
    if not sock then
        return nil, msg
    end

    return get_stations(sock, msg, ifname)
end

local function get_protocol_features(sock, msg, phyid)
    msg:put_attr_u32(nl80211.ATTR_WIPHY, phyid)
    local features

    local ok, err = sock:request_dump(msg, function(reply, nlh)
        if nlh.type < nl.NLMSG_MIN_TYPE then
            return
        end

        features = 0

        local attrs = reply:parse_attr(genl.GENLMSGHDR_SIZE)
        if attrs and attrs[nl80211.ATTR_PROTOCOL_FEATURES] then
            features = nl.attr_get_u32(attrs[nl80211.ATTR_PROTOCOL_FEATURES])
        end

        return true
    end)
    if not ok then
        return nil, err
    end

    if features == nil then
        return nil, 'no msg responsed'
    end

    return features
end

--- Get protocol features bitmask.
--
-- `phy` may be a PHY name or PHY index.
--
-- @function get_protocol_features
-- @tparam string|int phy PHY name or index.
-- @treturn int features Bitmask.
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
function M.get_protocol_features(phy)
    local phyid

    if type(phy) == 'string' then
        phyid = M.phy_lookup(phy)
        if not phyid then
            return nil, string.format('"%s" not exists', phy)
        end
    elseif type(phy) == 'number' then
        phyid = phy
    else
        error('invalid phy')
    end

    local sock<close>, msg = prepare_send_cmd(nl80211.CMD_GET_PROTOCOL_FEATURES)
    if not sock then
        return nil, msg
    end

    return get_protocol_features(sock, msg, phyid)
end

local function parse_freqlist(attrs, freqlist)
    for band, band_data in pairs(attrs) do
        local band_attrs = nl.parse_attr_nested(band_data)

        if band_attrs[nl80211.BAND_ATTR_FREQS] then
            for _, freq_data in pairs(nl.parse_attr_nested(band_attrs[nl80211.BAND_ATTR_FREQS])) do
                local freq_attrs = nl.parse_attr_nested(freq_data)
                local info = { band = band }

                if band == nl80211.BAND_2GHZ then
                    info.band = 2.4
                elseif band == nl80211.BAND_5GHZ then
                    info.band = 5
                elseif band == nl80211.BAND_60GHZ then
                    info.band = 60
                elseif band == nl80211.BAND_6GHZ then
                    info.band = 6
                end

                info.freq = nl.attr_get_u32(freq_attrs[nl80211.FREQUENCY_ATTR_FREQ])
                info.channel = M.freq_to_channel(info.freq)

                local flags = {}

                if freq_attrs[nl80211.FREQUENCY_ATTR_NO_HT40_MINUS] then
                    flags['NO_HT40+'] = true
                end

                if freq_attrs[nl80211.FREQUENCY_ATTR_NO_HT40_PLUS] then
                    flags['NO_HT40-'] = true
                end

                if freq_attrs[nl80211.FREQUENCY_ATTR_NO_80MHZ] then
                    flags['NO_80MHZ'] = true
                end

                if freq_attrs[nl80211.FREQUENCY_ATTR_NO_160MHZ] then
                    flags['NO_160MHZ'] = true
                end

                if freq_attrs[nl80211.FREQUENCY_ATTR_NO_20MHZ] then
                    flags['NO_20MHZ'] = true
                end

                if freq_attrs[nl80211.FREQUENCY_ATTR_NO_10MHZ] then
                    flags['NO_10MHZ'] = true
                end

                if freq_attrs[nl80211.FREQUENCY_ATTR_NO_320MHZ] then
                    flags['NO_320MHZ'] = true
                end

                if freq_attrs[nl80211.FREQUENCY_ATTR_NO_HE] then
                    info['NO_HE'] = true
                end

                if freq_attrs[nl80211.FREQUENCY_ATTR_NO_EHT] then
                    flags['NO_EHT'] = true
                end

                if freq_attrs[nl80211.FREQUENCY_ATTR_NO_IR] and not freq_attrs[nl80211.FREQUENCY_ATTR_RADAR] then
                    flags['NO_IR'] = true
                end

                if freq_attrs[nl80211.FREQUENCY_ATTR_RADAR] then
                    flags['RADAR'] = true
                end

                if freq_attrs[nl80211.FREQUENCY_ATTR_INDOOR_ONLY] then
                    flags['INDOOR_ONLY'] = true
                end

                info.flags = flags
                freqlist[#freqlist + 1] = info
            end
        end
    end
end

local function get_freqlist(sock, msg, phyid)
    msg:put_attr_u32(nl80211.ATTR_WIPHY, phyid)
    msg:put_attr_flag(nl80211.ATTR_SPLIT_WIPHY_DUMP)

    local freqlist = {}

    local ok, err = sock:request_dump(msg, function(reply, nlh)
        if nlh.type < nl.NLMSG_MIN_TYPE then
            return
        end

        local attrs = reply:parse_attr(genl.GENLMSGHDR_SIZE)

        if attrs[nl80211.ATTR_WIPHY_BANDS] then
            parse_freqlist(nl.parse_attr_nested(attrs[nl80211.ATTR_WIPHY_BANDS]), freqlist)
        end
    end)
    if not ok then
        return nil, err
    end

    return freqlist
end

--- Get supported frequencies for a PHY.
--
-- Returns an array of tables with fields:
--
-- - `band` (number)
-- - `freq` (int)
-- - `channel` (int)
-- - `flags` (table)
--
-- @function get_freqlist
-- @tparam string|int phy PHY name or index.
-- @treturn table freqlist
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
function M.get_freqlist(phy)
    local phyid

    if type(phy) == 'string' then
        phyid = M.phy_lookup(phy)
        if not phyid then
            return nil, string.format('"%s" not exists', phy)
        end
    elseif type(phy) == 'number' then
        phyid = phy
    else
        error('invalid phy')
    end

    local sock<close>, msg = prepare_send_cmd(nl80211.CMD_GET_WIPHY, nl.NLM_F_DUMP)
    if not sock then
        return nil, msg
    end

    return get_freqlist(sock, msg, phyid)
end

local function get_link_bss(sock, msg, ifname)
    local ifidx = socket.if_nametoindex(ifname)
    if not ifidx then
        return nil, 'no dev'
    end

    msg:put_attr_u32(nl80211.ATTR_IFINDEX, ifidx)

    local found

    local ok, err = sock:request_dump(msg, function(reply, nlh)
        if nlh.type < nl.NLMSG_MIN_TYPE then
            return
        end

        local attrs = reply:parse_attr(genl.GENLMSGHDR_SIZE)
        if attrs[nl80211.ATTR_BSS] then
            local bss = parse_bss(attrs[nl80211.ATTR_BSS])
            if bss then
                if bss.status == 'associated' or bss.status == 'ibss_joined' then
                    found = bss
                    return true
                end
            end
        end
    end)
    if not ok then
        return nil, err
    end

    return found
end

--- Get currently associated BSS on an interface.
--
-- This performs a scan dump and finds an entry with `status` of `associated`
-- (or `ibss_joined`). If possible, it also augments the BSS table with station
-- statistics (rates, bytes, signal, etc.).
--
-- @function get_link
-- @tparam string ifname Interface name.
-- @treturn bss info
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
function M.get_link(ifname)
    if type(ifname) ~= 'string' then
        error('invalid ifname')
    end

    local sock<close>, msg = prepare_send_cmd(nl80211.CMD_GET_SCAN, nl.NLM_F_DUMP)
    if not sock then
        return nil, msg
    end

    local bss = get_link_bss(sock, msg, ifname)
    if not bss then
        return nil, 'not connected'
    end

    local sta = M.get_station(ifname, bss.bssid)
    if sta then
        bss.rx_bytes = sta.rx_bytes
        bss.rx_packets = sta.rx_packets
        bss.tx_bytes = sta.tx_bytes
        bss.tx_packets = sta.tx_packets
        bss.tx_rate = sta.tx_rate
        bss.rx_rate = sta.rx_rate
        bss.signal = sta.signal
        bss.ack_signal_avg = sta.ack_signal_avg
    end

    return bss
end

return setmetatable(M, { __index = nl80211 })
