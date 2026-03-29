#!/usr/bin/env eco

local eco = require 'eco'
local test = require 'test'

local function shell_status(cmd)
    local ok, why, code = os.execute(cmd)

    if type(ok) == 'number' then
        return ok
    end

    if ok == true and why == 'exit' then
        return code
    end

    return -1
end

local function write_file(path, content)
    local f = assert(io.open(path, 'wb'))
    f:write(content)
    f:close()
end

-- Constants exported by eco.c
assert(type(eco.VERSION) == 'string')
assert(math.type(eco.VERSION_MAJOR) == 'integer')
assert(math.type(eco.VERSION_MINOR) == 'integer')
assert(math.type(eco.VERSION_PATCH) == 'integer')
assert(math.type(eco.READ) == 'integer')
assert(math.type(eco.WRITE) == 'integer')
assert(eco.READ ~= eco.WRITE)

-- set_panic_hook argument validation and normal setup.
test.expect_error(function()
    eco.set_panic_hook(1)
end, 'set_panic_hook should reject non-function')

local panic_calls = 0
eco.set_panic_hook(function()
    panic_calls = panic_calls + 1
end)

test.expect_error_contains(function()
    eco.set_watchdog_timeout(-1)
end, 'range', 'set_watchdog_timeout should reject negative timeout')

test.expect_error_contains(function()
    eco.set_watchdog_timeout(5001)
end, 'range', 'set_watchdog_timeout should reject too large timeout')

test.expect_error_contains(function()
    eco.set_watchdog_timeout('x')
end, 'number expected', 'set_watchdog_timeout should reject non-integer input')

eco.set_watchdog_timeout(0)
eco.set_watchdog_timeout(1000)

do
    local script = os.tmpname()

    write_file(script, [[
local eco = require 'eco'
eco.set_watchdog_timeout(1)
eco.run(function()
    local until_at = os.clock() + 0.03
    while os.clock() < until_at do end
end)
]])

    local status = shell_status('eco ' .. script .. ' >/dev/null 2>&1')
    os.remove(script)

    assert(status ~= 0, 'watchdog should terminate long-running coroutine with non-zero exit')
end

do
    local script = os.tmpname()

    write_file(script, [[
local eco = require 'eco'
eco.set_watchdog_timeout(0)
eco.run(function()
    local until_at = os.clock() + 0.03
    while os.clock() < until_at do end
end)
print('ok')
]])

    local status = shell_status('eco ' .. script .. ' >/dev/null 2>&1')
    os.remove(script)

    assert(status == 0, 'watchdog=0 should disable timeout checks')
end

local yielded_co
local done = {}

eco.run(function()
    yielded_co = coroutine.running()
    coroutine.yield()

    done.resumed = true
    eco.sleep(0.01)
    done.slept = true
end)

eco.run(function()
    local ok = false

    for _, co in ipairs(eco.all()) do
        if co == yielded_co then
            ok = true
            break
        end
    end

    assert(ok, 'eco.all() should include suspended coroutine')
    assert(eco.count() >= 2, 'eco.count() should include active coroutines')

    done.enumerated = true
end)

eco.run(function()
    eco.sleep(0.01)
    eco.resume(yielded_co)
    done.resumer = true
end)

test.wait_until('eco run/resume flow completed', function()
    return done.enumerated and done.resumer and done.resumed and done.slept
end, 2.0)

assert(done.enumerated, 'all/count coroutine did not run')
assert(done.resumer, 'resume coroutine did not run')
assert(done.resumed, 'target coroutine was not resumed')
assert(done.slept, 'sleep did not wake coroutine')

eco.run(function()
    eco.sleep(0.02)
end)

assert(eco.count() >= 1, 'precondition: there should be a pending coroutine before init()')

test.expect_error_contains(function()
    eco._init()
end, 'only allowed', 'init() should be child-only')

test.wait_until('pending coroutine drained', function()
    return eco.count() <= 1
end, 2.0)

assert(panic_calls == 0, 'panic hook should not be called in normal flow')

-- GC regression: completed coroutines should not be kept alive by scheduler state.
local weak_co = setmetatable({}, { __mode = 'v' })
local weak_ready = false

eco.run(function()
    weak_co[1] = coroutine.running()
    weak_ready = true
end)

test.wait_until('weak coroutine created', function()
    return weak_ready
end, 2.0)

test.full_gc()
assert(weak_co[1] == nil, 'completed coroutine should be collectible after full GC')

-- Leak regression: memory should stabilize across repeated coroutine/timer bursts.
local function burst_coroutines(rounds, n)
    for _ = 1, rounds do
        local done_count = 0

        for _ = 1, n do
            eco.run(function()
                eco.sleep(0.002)
                done_count = done_count + 1
            end)
        end

        test.wait_until('coroutine burst round completed', function()
            return done_count == n
        end, 5.0)
    end
end

local base_mem_kb = test.lua_mem_kb()

burst_coroutines(20, 2000)
local after_first_kb = test.lua_mem_kb()

burst_coroutines(20, 2000)
local after_second_kb = test.lua_mem_kb()

local growth_first_kb = after_first_kb - base_mem_kb
local growth_second_kb = after_second_kb - after_first_kb
local plateau_limit_kb = math.max(128, growth_first_kb * 0.25)

assert(growth_first_kb < 8192,
    string.format('unexpectedly large initial memory growth: %.2f KB', growth_first_kb))

assert(growth_second_kb <= plateau_limit_kb,
    string.format('memory keeps growing across equal bursts: first %.2f KB, second %.2f KB (limit %.2f KB)',
            growth_first_kb, growth_second_kb, plateau_limit_kb))

print('eco core tests passed')
