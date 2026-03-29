#!/usr/bin/env eco

local base64 = require 'eco.encoding.base64'
local test = require 'test'

local function run_case(name, fn)
    local ok, err = pcall(fn)
    assert(ok, name .. ': ' .. tostring(err))
end

run_case('known vectors encode/decode', function()
    local vectors = {
        { '', '' },
        { 'f', 'Zg==' },
        { 'fo', 'Zm8=' },
        { 'foo', 'Zm9v' },
        { 'foob', 'Zm9vYg==' },
        { 'fooba', 'Zm9vYmE=' },
        { 'foobar', 'Zm9vYmFy' },
    }

    for i = 1, #vectors do
        local raw = vectors[i][1]
        local b64 = vectors[i][2]

        assert(base64.encode(raw) == b64, 'encode vector mismatch at #' .. i)

        local decoded, err = base64.decode(b64)
        assert(decoded == raw, err or ('decode vector mismatch at #' .. i))
    end
end)

run_case('binary roundtrip', function()
    local raw = string.char(0, 1, 2, 3, 254, 255) .. 'eco' .. string.char(0)

    local encoded = base64.encode(raw)
    local decoded, err = base64.decode(encoded)

    assert(decoded == raw, err)
end)

run_case('decode malformed input', function()
    local out, err = base64.decode('abc')
    assert(out == nil and err == 'input is malformed', 'decode should reject non-4-multiple length')

    out, err = base64.decode('ab#=')
    assert(out == nil and err == 'input is malformed', 'decode should reject invalid characters')

    out, err = base64.decode('ab\n=')
    assert(out == nil and err == 'input is malformed', 'decode should reject control characters')
end)

run_case('argument validation', function()
    test.expect_error(function()
        base64.encode({})
    end, 'encode should reject non-string-like input')

    test.expect_error(function()
        base64.decode({})
    end, 'decode should reject non-string-like input')
end)

-- Stress + memory plateau regression for repeated encode/decode bursts.
do
    local function burst(rounds, n)
        local total = 0

        for r = 1, rounds do
            for i = 1, n do
                local raw = string.format('payload-%d-%d-%s', r, i, string.rep('x', (i % 33)))
                local b64 = base64.encode(raw)
                local out, err = base64.decode(b64)

                assert(out == raw, err)
                total = total + 1
            end
        end

        return total
    end

    local rounds = 6
    local n = 1500
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
           string.format('unexpectedly large initial base64 memory growth: %.2f KB', growth_first_kb))

    assert(growth_second_kb <= plateau_limit_kb,
           string.format('base64 memory keeps growing across equal bursts: first %.2f KB, second %.2f KB (limit %.2f KB)',
                         growth_first_kb, growth_second_kb, plateau_limit_kb))
end

print('base64 tests passed')
