#!/usr/bin/env eco

local md5 = require 'eco.hash.md5'
local sha1 = require 'eco.hash.sha1'
local sha256 = require 'eco.hash.sha256'
local hmac = require 'eco.hash.hmac'
local hex = require 'eco.encoding.hex'
local test = require 'test'

local function run_case(name, fn)
    local ok, err = pcall(fn)
    assert(ok, name .. ': ' .. tostring(err))
end

assert(md5.mtname == 'struct md5_ctx *')
assert(sha1.mtname == 'struct sha1_ctx *')
assert(sha256.mtname == 'struct sha256_ctx *')

run_case('sum known vectors', function()
    assert(hex.encode(md5.sum('abc')) == '900150983cd24fb0d6963f7d28e17f72')
    assert(hex.encode(sha1.sum('abc')) == 'a9993e364706816aba3e25717850c26c9cd0d89d')
    assert(hex.encode(sha256.sum('abc')) == 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad')

    assert(#md5.sum('') == 16)
    assert(#sha1.sum('') == 20)
    assert(#sha256.sum('') == 32)
end)

run_case('incremental equals one-shot', function()
    local c1 = md5.new()
    c1:update('a')
    c1:update('b')
    c1:update('c')
    assert(hex.encode(c1:final()) == hex.encode(md5.sum('abc')))

    local c2 = sha1.new()
    c2:update('a')
    c2:update('b')
    c2:update('c')
    assert(hex.encode(c2:final()) == hex.encode(sha1.sum('abc')))

    local c3 = sha256.new()
    c3:update('a')
    c3:update('b')
    c3:update('c')
    assert(hex.encode(c3:final()) == hex.encode(sha256.sum('abc')))
end)

run_case('sha1 512MiB zero stream regression', function()
    local chunk = string.rep('\0', 1024 * 1024)
    local ctx = sha1.new()

    for _ = 1, 512 do
        ctx:update(chunk)
    end

    assert(hex.encode(ctx:final()) == '5b088492c9f4778f409b7ae61477dec124c99033')
end)

run_case('hmac vectors all hash modules', function()
    local key = 'key'
    local data = 'The quick brown fox jumps over the lazy dog'

    assert(hex.encode(hmac.sum(md5, key, data)) == '80070713463e7749b90c2dc24911e275')
    assert(hex.encode(hmac.sum(sha1, key, data)) == 'de7c9b85b8b78aa6bc8a7a36f70a90701c9db4d9')
    assert(hex.encode(hmac.sum(sha256, key, data)) == 'f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8')
end)

run_case('hmac incremental and long key path', function()
    local long_key = string.rep('k', 100)
    local data = 'abcdef0123456789'

    local one_shot = hmac.sum(sha256, long_key, data)

    local ctx = hmac.new(sha256, long_key)
    ctx:update('abc')
    ctx:update('def')
    ctx:update('0123')
    ctx:update('456789')

    assert(hex.encode(ctx:final()) == hex.encode(one_shot))
end)

run_case('argument validation', function()
    test.expect_error(function()
        md5.sum({})
    end, 'md5.sum should reject non-string-like input')

    test.expect_error(function()
        sha1.sum({})
    end, 'sha1.sum should reject non-string-like input')

    test.expect_error(function()
        sha256.sum({})
    end, 'sha256.sum should reject non-string-like input')

    local c1 = md5.new()
    local c2 = sha1.new()
    local c3 = sha256.new()

    test.expect_error(function()
        c1:update({})
    end, 'md5:update should reject non-string-like input')

    test.expect_error(function()
        c2:update({})
    end, 'sha1:update should reject non-string-like input')

    test.expect_error(function()
        c3:update({})
    end, 'sha256:update should reject non-string-like input')

    test.expect_error(function()
        hmac.new({}, 'k')
    end, 'hmac.new should reject non-hash module')

    test.expect_error(function()
        hmac.new(md5, false)
    end, 'hmac.new should reject non-string key')

    local h = hmac.new(md5, 'k')
    test.expect_error(function()
        h:update(false)
    end, 'hmac:update should reject non-string data')
end)

-- GC regression: hash/hmac contexts should be collectible when unreachable.
do
    local weak = setmetatable({}, { __mode = 'v' })

    do
        local m = md5.new()
        local s1 = sha1.new()
        local s256 = sha256.new()
        local hm = hmac.new(sha256, 'key')

        weak.m = m
        weak.s1 = s1
        weak.s256 = s256
        weak.hm = hm

        m:update('abc')
        s1:update('abc')
        s256:update('abc')
        hm:update('abc')

        m:final()
        s1:final()
        s256:final()
        hm:final()
    end

    test.full_gc()

    assert(weak.m == nil and weak.s1 == nil and weak.s256 == nil and weak.hm == nil,
           'hash and hmac context objects should be collectible')
end

-- Stress + memory plateau regression for repeated hashing bursts.
do
    local function burst(rounds, n)
        local total = 0

        for r = 1, rounds do
            for i = 1, n do
                local payload = string.format('payload-%d-%d', r, i)

                md5.sum(payload)
                sha1.sum(payload)
                sha256.sum(payload)
                hmac.sum(sha256, 'k', payload)

                total = total + 1
            end
        end

        return total
    end

    local rounds = 6
    local n = 1200
    local expected = rounds * n

    local base_mem_kb = test.lua_mem_kb()

    assert(burst(rounds, n) == expected)
    local after_first_kb = test.lua_mem_kb()

    assert(burst(rounds, n) == expected)
    local after_second_kb = test.lua_mem_kb()

    local growth_first_kb = after_first_kb - base_mem_kb
    local growth_second_kb = after_second_kb - after_first_kb
    local plateau_limit_kb = math.max(128, growth_first_kb * 0.30)

    assert(growth_first_kb < 8192,
           string.format('unexpectedly large initial hash memory growth: %.2f KB', growth_first_kb))

    assert(growth_second_kb <= plateau_limit_kb,
           string.format('hash memory keeps growing across equal bursts: first %.2f KB, second %.2f KB (limit %.2f KB)',
                         growth_first_kb, growth_second_kb, plateau_limit_kb))
end

print('hash tests passed')
