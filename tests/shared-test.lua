#!/usr/bin/env eco

local shared = require 'eco.shared'
local time = require 'eco.time'
local sys = require 'eco.sys'
local eco = require 'eco'
local test = require 'test'

local function assert_type(v, t, msg)
    assert(type(v) == t, msg)
end

local function sorted_keys(tbl)
    table.sort(tbl)
    return tbl
end

local name = string.format('shared-test-%d-%f', sys.getpid(), time.now() * 1000)

test.run_case_async('shared semantics', function()
    local d, err
    local owner, peer

    -- API-level input validation for names.
    d, err = shared.new('bad/name', 128)
    assert(d == nil and err, 'shared.new should reject invalid name')

    d, err = shared.get('bad/name')
    assert(d == nil and err, 'shared.get should reject invalid name')

    -- Size validation is an argument error (throws).
    test.expect_error(function()
        shared.new('bad-size', 0)
    end, 'shared.new(size<=0) should throw')

    owner, err = shared.new(name, 4096)
    assert(owner, err)

    d, err = shared.new(name, 128)
    assert(d == nil and err, 'shared.new should fail for duplicate name')

    peer, err = shared.get(name)
    assert(peer, err)

    -- set/get for all supported value types.
    assert(owner:set('k_bool', true))
    assert(owner:set('k_num', 1.5))
    assert(owner:set('k_str', 'hello'))

    assert(owner:get('k_bool') == true)
    assert(owner:get('k_num') == 1.5)
    assert(owner:get('k_str') == 'hello')

    -- Shared visibility across handles.
    assert(peer:get('k_num') == 1.5)
    assert(peer:get('k_str') == 'hello')

    local ok, set_err = owner:set('k_bad_type', {})
    assert(ok == nil, 'set should reject non scalar values')
    assert_type(set_err, 'string', 'set should return error string for bad type')

    -- Optional exptime must be finite.
    test.expect_error(function()
        owner:set('k_nan', 1, 0 / 0)
    end, 'set exptime must reject NaN')

    -- del semantics.
    assert(owner:del('k_str') == true)
    assert(owner:get('k_str') == nil)
    assert(owner:del('k_str') == false)
    assert(owner:get('missing') == nil)

    -- ttl semantics: missing => nil; permanent => 0.
    assert(owner:ttl('missing') == nil)
    assert(owner:set('k_perm', 'v'))
    assert(owner:ttl('k_perm') == 0)

    -- Key expiration from set().
    assert(owner:set('k_exp', 'v', 0.05))
    local ttl = owner:ttl('k_exp')
    assert(ttl and ttl > 0, 'ttl should be > 0 for expiring key')
    time.sleep(0.08)
    assert(owner:get('k_exp') == nil)
    assert(owner:ttl('k_exp') == nil)

    -- expire(): positive set, non-positive clear.
    assert(owner:set('k_expire', 'x', 0.05))
    assert(owner:expire('k_expire', -1))
    assert(owner:ttl('k_expire') == 0)
    time.sleep(0.08)
    assert(owner:get('k_expire') == 'x')

    assert(owner:expire('k_expire', 0.05))
    time.sleep(0.08)
    assert(owner:get('k_expire') == nil)
    assert(owner:expire('k_expire', 0.1) == nil)

    test.expect_error(function()
        owner:expire('k_perm', 0 / 0)
    end, 'expire exptime must reject NaN')

    -- incr() semantics.
    assert(owner:set('k_counter', 1, 0.3))
    local before = owner:ttl('k_counter')
    assert(before and before > 0)

    local n = owner:incr('k_counter', 2)
    assert(n == 3)

    local after = owner:ttl('k_counter')
    assert(after and after > 0, 'ttl should still exist when incr omits exptime')

    n = owner:incr('k_counter', 1, 0.6)
    assert(n == 4)
    local refreshed = owner:ttl('k_counter')
    assert(refreshed and refreshed > 0.4, 'ttl should refresh when incr provides exptime')

    assert(owner:incr('k_missing_counter', 1) == nil)

    assert(owner:set('k_not_number', 'abc'))
    n, err = owner:incr('k_not_number', 1)
    assert(n == nil and err == 'not a number')

    test.expect_error(function()
        owner:incr('k_counter', 0 / 0)
    end, 'incr delta must reject NaN')

    test.expect_error(function()
        owner:incr('k_counter', 1, 0 / 0)
    end, 'incr exptime must reject NaN')

    -- get_keys() and flush_all().
    owner:flush_all()
    assert(#owner:get_keys() == 0)

    assert(owner:set('k1', 1))
    assert(owner:set('k2', 'v2'))
    assert(owner:set('k3', true, 0.05))
    time.sleep(0.08)

    local keys = sorted_keys(owner:get_keys())
    assert(#keys == 2 and keys[1] == 'k1' and keys[2] == 'k2')

    owner:flush_all()
    assert(owner:get('k1') == nil)
    assert(#owner:get_keys() == 0)

    -- no memory: value cannot fit in a tiny dictionary.
    local tiny_name = name .. '-tiny'
    local tiny

    tiny, err = shared.new(tiny_name, 64)
    assert(tiny, err)

    ok, set_err = tiny:set('x', string.rep('z', 256))
    assert(ok == nil and set_err == 'no memory', 'set should return no memory when item is too large')

    tiny:close()

    -- gc reclaim: tombstoned items should be reclaimed on the next pressured set().
    local gc_name = name .. '-gc'
    local gc
    local inserted = {}
    local payload = string.rep('p', 48)

    gc, err = shared.new(gc_name, 320)
    assert(gc, err)

    while true do
        local k = 'g' .. tostring(#inserted + 1)

        ok, set_err = gc:set(k, payload)
        if ok then
            inserted[#inserted + 1] = k
        else
            assert(ok == nil and set_err == 'no memory', 'fill loop should end with no memory')
            break
        end
    end

    assert(#inserted >= 2, 'gc reclaim test requires multiple inserted items')
    assert(gc:del(inserted[1]) == true)

    ok, set_err = gc:set(inserted[1], payload)
    assert(ok == true, set_err or 'set should succeed after gc reclaim')
    assert(gc:get(inserted[1]) == payload)

    gc:close()

    -- Owner close should remove backing shared-memory file.
    assert(peer:set('k_after_owner_close', 'ok'))
    owner:close()
    owner:close()

    -- Existing handle still works after owner close.
    assert(peer:get('k_after_owner_close') == 'ok')

    -- But opening by name again should fail.
    d, err = shared.get(name)
    assert(d == nil and err, 'shared.get should fail after owner close removes file')

    -- Non-owner close is idempotent and should not throw.
    peer:close()
    peer:close()

    print('shared tests passed')
end)
