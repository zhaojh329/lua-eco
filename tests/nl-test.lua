#!/usr/bin/env eco

local nl = require 'eco.internal.nl'
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

print('netlink tests passed')
