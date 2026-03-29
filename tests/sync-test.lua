#!/usr/bin/env eco

local eco = require 'eco'
local sync = require 'eco.sync'
local ifile = require 'eco.internal.file'
local test = require 'test'

-- cond: signal data, fallback true, timeout and idempotent close.
test.run_case_sync('cond wait/signal/timeout', function()
    local c = assert(sync.cond())

    assert(c:signal('none') == false, 'signal should return false when no waiters')

    eco.run(function()
        local v, err = c:wait(1.0)
        assert(v == 'payload' and err == nil)

        v, err = c:wait(1.0)
        assert(v == true and err == nil, 'falsy signal data should map to true')

        v, err = c:wait(0.03)
        assert(v == nil and err == 'timeout')

        c:close()
        c:close()
    end)

    eco.run(function()
        eco.sleep(0.01)
        assert(c:signal('payload') == true)

        eco.sleep(0.01)
        assert(c:signal(false) == true)
    end)
end)

-- cond: broadcast wakes all waiters.
test.run_case_sync('cond broadcast', function()
    local c = assert(sync.cond())
    local n = 24
    local woken = 0

    for _ = 1, n do
        eco.run(function()
            local ok, err = c:wait(1.0)
            assert(ok == true and err == nil)
            woken = woken + 1
        end)
    end

    eco.run(function()
        eco.sleep(0.02)
        local cnt = c:broadcast()
        assert(cnt == n)
    end)

    eco.run(function()
        test.wait_until('broadcast should wake all waiters', function()
            return woken == n
        end, 2.0, 0.01)
        c:close()
    end)
end)

-- mutex: lock exclusion, timeout and unlock error.
test.run_case_sync('mutex lock/unlock semantics', function()
    local m = sync.mutex()

    eco.run(function()
        local ok, err = m:lock()
        assert(ok == true and err == nil)

        eco.sleep(0.06)

        m:unlock()
    end)

    eco.run(function()
        eco.sleep(0.01)

        local ok, err = m:lock(0.02)
        assert(ok == nil and err == 'timeout')

        ok, err = m:lock(0.2)
        assert(ok == true and err == nil)

        m:unlock()

        test.expect_error_contains(function()
            m:unlock()
        end, 'unlock of unlocked mutex', 'unlock on unlocked mutex should throw')
    end)
end)

-- waitgroup: wait success, timeout and negative counter errors.
test.run_case_sync('waitgroup semantics', function()
    local wg = sync.waitgroup()

    assert(wg:wait(0.01) == true, 'waitgroup with zero counter should return immediately')

    wg:add(3)

    for i = 1, 3 do
        eco.run(function()
            eco.sleep(0.01 * i)
            wg:done()
        end)
    end

    eco.run(function()
        local ok, err = wg:wait(1.0)
        assert(ok == true and err == nil)

        test.expect_error_contains(function()
            wg:add(-1)
        end, 'negative waitgroup counter', 'add() should reject negative counter')

        test.expect_error_contains(function()
            wg:done()
        end, 'negative wait group counter', 'done() should reject negative counter')
    end)
end)

test.run_case_sync('waitgroup timeout', function()
    local wg = sync.waitgroup()
    wg:add(1)

    eco.run(function()
        local ok, err = wg:wait(0.03)
        assert(ok == nil and err == 'timeout')
    end)

    eco.run(function()
        eco.sleep(0.08)
        wg:done()
    end)
end)

-- Stress: many concurrent lock/unlock cycles should preserve counter correctness.
test.run_case_sync('mutex stress counter correctness', function()
    local m = sync.mutex()
    local workers = 64
    local loops = 150
    local total = 0
    local finished = 0

    for _ = 1, workers do
        eco.run(function()
            for _ = 1, loops do
                local ok, err = m:lock(1.0)
                assert(ok == true, err)
                total = total + 1
                m:unlock()
            end

            finished = finished + 1
        end)
    end

    eco.run(function()
        test.wait_until('mutex stress timeout', function()
            return finished == workers
        end, 8.0, 0.01)
        assert(total == workers * loops, string.format('counter mismatch: %d/%d', total, workers * loops))
    end)
end)

-- GC regression: sync wrappers should be collectible and close underlying eventfd.
do
    local weak = setmetatable({}, { __mode = 'v' })
    local cfd, mfd, wfd

    test.run_case_sync('sync gc closes eventfd', function()
        local c = assert(sync.cond())
        cfd = c.efd
        weak.c = c

        local m = sync.mutex()
        mfd = m.cond.efd
        weak.m = m

        local wg = sync.waitgroup()
        wfd = wg.cond.efd
        weak.wg = wg
    end)

    test.full_gc()

    assert(weak.c == nil and weak.m == nil and weak.wg == nil,
           'sync objects should be collectible after references are dropped')

    local ok, err = ifile.close(cfd)
    assert(ok == nil and type(err) == 'string', 'cond eventfd should be closed by GC path')

    ok, err = ifile.close(mfd)
    assert(ok == nil and type(err) == 'string', 'mutex cond eventfd should be closed by GC path')

    ok, err = ifile.close(wfd)
    assert(ok == nil and type(err) == 'string', 'waitgroup cond eventfd should be closed by GC path')
end

-- Memory leak regression: repeated primitive creation/usage should plateau.
do
    local function sync_burst(n)
        local done = 0

        for _ = 1, n do
            local c = assert(sync.cond())
            local m = sync.mutex()
            local wg = sync.waitgroup()

            wg:add(1)

            eco.run(function()
                local ok, err = m:lock(0.5)
                assert(ok == true, err)
                m:unlock()

                assert(c:signal('x') == false)
                c:close()
                wg:done()
            end)

            eco.run(function()
                local ok, err = wg:wait(0.5)
                assert(ok == true, err)
                done = done + 1
            end)
        end

        test.wait_until('sync burst completes', function()
            return done == n
        end, 5.0)
    end

    local base_mem_kb = test.lua_mem_kb()

    sync_burst(400)
    local after_first_kb = test.lua_mem_kb()

    sync_burst(400)
    local after_second_kb = test.lua_mem_kb()

    local growth_first_kb = after_first_kb - base_mem_kb
    local growth_second_kb = after_second_kb - after_first_kb
    local plateau_limit_kb = math.max(128, growth_first_kb * 0.35)

    assert(growth_first_kb < 8192,
           string.format('unexpectedly large initial sync memory growth: %.2f KB', growth_first_kb))

    assert(growth_second_kb <= plateau_limit_kb,
           string.format('sync memory keeps growing across equal bursts: first %.2f KB, second %.2f KB (limit %.2f KB)',
                         growth_first_kb, growth_second_kb, plateau_limit_kb))
end

print('sync tests passed')
