#!/usr/bin/env eco

local nl = require 'eco.internal.nl'
local nl80211 = require 'eco.internal.nl80211'
local test = require 'test'

local function attrs_from_msg(msg, offset)
    local rx = nl.nlmsg_ker(msg:binary())
    assert(rx:next())

    local attrs, err = rx:parse_attr(offset or 0)
    assert(attrs, err)

    return attrs
end

local function malformed_attr(len, typ)
    return string.pack('=I2I2', len, typ or 1)
end

local function run_case(name, fn)
    local ok, err = pcall(fn)
    assert(ok, name .. ': ' .. tostring(err))
end

run_case('attribute accessors validate and decode payloads', function()
    local msg = nl.nlmsg(0, 0)

    assert(msg:put_attr(1, string.pack('=I4', 0x12345678)))
    assert(msg:put_attr_strz(2, 'eth0'))
    assert(msg:put_attr_flag(3))
    assert(msg:put_attr_nest_start(4))
    assert(msg:put_attr(1, string.char(7)))
    assert(msg:put_attr_nest_end())

    local attrs = attrs_from_msg(msg)
    local nested = nl.parse_attr_nested(attrs[4])

    assert(nl.attr_get_u32(attrs[1]) == 0x12345678)
    assert(nl.attr_get_str(attrs[2]) == 'eth0')
    assert(nl.attr_get_payload(attrs[3]) == '')
    assert(nl.attr_get_u8(nested[1]) == 7)
end)

run_case('attribute accessors reject malformed strings', function()
    local no_nul = attrs_from_msg(nl.nlmsg(0, 0):put_attr_str(1, 'abc'))[1]
    local flag = attrs_from_msg(nl.nlmsg(0, 0):put_attr_flag(1))[1]
    local declared_too_long = malformed_attr(8)

    test.expect_error(function()
        nl.attr_get_u8('')
    end, 'short attr should be rejected')

    test.expect_error(function()
        nl.attr_get_payload(declared_too_long)
    end, 'attr with length beyond string should be rejected')

    test.expect_error(function()
        nl.attr_get_u64(flag)
    end, 'short payload should be rejected')

    test.expect_error(function()
        nl.attr_get_str(no_nul)
    end, 'non-NUL-terminated string attr should be rejected')

    test.expect_error(function()
        nl.parse_attr_nested(declared_too_long)
    end, 'malformed nested attr should be rejected')
end)

run_case('builder rejects invalid arguments and malformed attrs', function()
    test.expect_error(function()
        nl.nlmsg(0, 0, 0, -1)
    end, 'negative nlmsg size should be rejected')

    test.expect_error(function()
        nl.nlmsg(0, 0, 0, math.maxinteger)
    end, 'oversized nlmsg size should be rejected')

    test.expect_error(function()
        nl.nlmsg(0, 0):put_attr_str(1, nil)
    end, 'put_attr_str should reject nil')

    test.expect_error(function()
        nl.nlmsg(0, 0):put_attr_strz(1, nil)
    end, 'put_attr_strz should reject nil')

    local msg = nl.nlmsg(0, 0)
    assert(msg:put(malformed_attr(8)))

    local rx = nl.nlmsg_ker(msg:binary())
    assert(rx:next())

    local attrs, err = rx:parse_attr(0)
    assert(attrs == nil and err == 'malformed attributes')
end)

run_case('nl80211 sta flag payloads are bounds checked', function()
    local STA_FLAG_AUTHORIZED = 1
    local STA_FLAG_SHORT_PREAMBLE = 2
    local STA_FLAG_WME = 3
    local STA_FLAG_MFP = 4
    local STA_FLAG_AUTHENTICATED = 5
    local STA_FLAG_ASSOCIATED = 7
    local mask = (1 << STA_FLAG_AUTHORIZED) |
            (1 << STA_FLAG_SHORT_PREAMBLE) |
            (1 << STA_FLAG_WME) |
            (1 << STA_FLAG_MFP) |
            (1 << STA_FLAG_AUTHENTICATED) |
            (1 << STA_FLAG_ASSOCIATED)
    local set = (1 << STA_FLAG_AUTHORIZED) |
            (1 << STA_FLAG_SHORT_PREAMBLE) |
            (1 << STA_FLAG_AUTHENTICATED)

    local flags = nl80211.parse_sta_flag_update(string.pack('=I4I4', mask, set))
    assert(flags.authorized == true)
    assert(flags.authenticated == true)
    assert(flags.associated == false)
    assert(flags.preamble == 'short')
    assert(flags.wme == false)
    assert(flags.mfp == false)

    flags = nl80211.parse_sta_flag_update(string.pack('=I4I4', mask, set) .. 'pad')
    assert(flags.authorized == true)

    test.expect_error_contains(function()
        nl80211.parse_sta_flag_update(string.rep('\0', 7))
    end, 'invalid sta flags', 'short sta flag payload should be rejected')
end)

print('netlink tests passed')
