#!/usr/bin/env eco

local ok_mod, uci = pcall(require, 'eco.uci')
if not ok_mod then
    print('skip uci tests: ' .. tostring(uci))
    os.exit(0)
end

local test = require 'test'
local sys = require 'eco.sys'
local time = require 'eco.time'

local function mkdir_p(path)
    assert(os.execute('mkdir -p ' .. path) == true)
end

local function rm_rf(path)
    os.execute('rm -rf ' .. path)
end

local function write_text(path, content)
    local f = assert(io.open(path, 'wb'))
    f:write(content)
    f:close()
end

local tmp_base = string.format('/tmp/eco-uci-test-%d-%d', sys.getpid(), math.floor(time.now() * 1000))
local confdir = tmp_base .. '/conf'
local savedir = tmp_base .. '/save'
local pkg = 'ecotest'
local pkg_file = confdir .. '/' .. pkg

local ok, err = xpcall(function()
    rm_rf(tmp_base)
    mkdir_p(confdir)
    mkdir_p(savedir)

    write_text(pkg_file, table.concat({
        "config demo 's1'",
        "\toption foo 'bar'",
        "\tlist arr 'x'",
        "\tlist arr 'y'",
        "",
        "config demo 's2'",
        "\toption foo 'baz'",
        ""
    }, '\n'))

    test.expect_error_contains(function()
        uci.cursor(confdir, savedir, tmp_base)
    end, 'Invalid args', 'cursor should reject too many arguments')

    local c = uci.cursor(confdir, savedir)
    assert(c)

    assert(c:get_confdir() == confdir)
    assert(c:get_savedir() == savedir)

    local cfgs, lerr = c:list_configs()
    assert(cfgs and lerr == nil)

    local seen_pkg = false
    for i = 1, #cfgs do
        if cfgs[i] == pkg then
            seen_pkg = true
            break
        end
    end
    assert(seen_pkg, 'list_configs should include test package')

    local l_ok, l_err = c:load(pkg)
    assert(l_ok == true and l_err == nil)

    local t, name = c:get(pkg, 's1')
    assert(t == 'demo' and name == 's1')

    local foo, gerr = c:get(pkg, 's1', 'foo')
    assert(foo == 'bar' and gerr == nil)

    local arr, aerr = c:get(pkg, 's1', 'arr')
    assert(type(arr) == 'table' and aerr == nil)
    assert(#arr == 2 and arr[1] == 'x' and arr[2] == 'y')

    local sec = c:get_all(pkg, 's1')
    assert(type(sec) == 'table')
    assert(sec['.type'] == 'demo' and sec['.name'] == 's1')
    assert(sec.foo == 'bar')

    local all = c:get_all(pkg)
    assert(type(all) == 'table' and type(all.s1) == 'table' and type(all.s2) == 'table')

    local foreach_n = 0
    local foreach_ok = c:foreach(pkg, 'demo', function(s)
        foreach_n = foreach_n + 1
        if foreach_n == 1 then
            return false
        end
        return true
    end)
    assert(foreach_ok == true)
    assert(foreach_n == 1, 'foreach should stop when callback returns false')

    local foreach_no_type_n = 0
    local foreach_no_type_ok = c:foreach(pkg, function(s)
        assert(type(s) == 'table')
        foreach_no_type_n = foreach_no_type_n + 1
        return true
    end)
    assert(foreach_no_type_ok == true)
    assert(foreach_no_type_n == 2, 'foreach without type should iterate all sections')

    local foreach_all_n = 0
    local foreach_all_ok = c:foreach(pkg, nil, function(s)
        assert(type(s) == 'table')
        foreach_all_n = foreach_all_n + 1
        return true
    end)
    assert(foreach_all_ok == true)
    assert(foreach_all_n == 2, 'foreach with nil type should iterate all sections')

    local each_iter = c:each(pkg, 'demo')
    assert(type(each_iter) == 'function')

    local each_n = 0
    for s in each_iter do
        each_n = each_n + 1
        assert(s['.type'] == 'demo')
    end
    assert(each_n == 2)

    local each_all_n = 0
    for s in c:each(pkg) do
        assert(type(s) == 'table')
        each_all_n = each_all_n + 1
    end
    assert(each_all_n == 2, 'each without type should iterate all sections')

    local each_nil_n = 0
    for s in c:each(pkg, nil) do
        assert(type(s) == 'table')
        each_nil_n = each_nil_n + 1
    end
    assert(each_nil_n == 2, 'each with nil type should iterate all sections')

    -- Reproducer for known foreach stack-growth issue:
    -- callback return values should not accumulate in C stack across iterations.
    do
        local repro_pkg = 'foreachleak'

        write_text(confdir .. '/' .. repro_pkg, table.concat({
            "config demo 's0'",
            "\toption v '0'",
            ""
        }, '\n'))

        assert(c:load(repro_pkg) == true)

        for i = 1, 3000 do
            local sid = assert(c:add(repro_pkg, 'demo'))
            assert(c:set(repro_pkg, sid, 'v', tostring(i)) == true)
        end

        test.full_gc()

        local base_kb = collectgarbage('count')
        local peak_kb = base_kb
        local iters = 0

        local foreach_ok2, foreach_err2 = pcall(function()
            c:foreach(repro_pkg, 'demo', function()
                iters = iters + 1

                -- If previous return values were properly released, this GC keeps memory near baseline.
                collectgarbage('collect')

                local payload = string.rep('x', 4096) .. tostring(iters)
                local now_kb = collectgarbage('count')

                if now_kb > peak_kb then
                    peak_kb = now_kb
                end

                return payload
            end)
        end)

        assert(foreach_ok2, foreach_err2)

        local peak_growth_kb = peak_kb - base_kb

        assert(peak_growth_kb < 2048,
               string.format('foreach callback return values seem leaked on stack: peak growth %.2f KB over %d iterations',
                             peak_growth_kb, iters))
    end

    local sid, adderr = c:add(pkg, 'demo')
    assert(type(sid) == 'string' and adderr == nil)

    assert(c:set(pkg, sid, 'foo', 'new') == true)
    assert(c:set(pkg, sid, 'items', { 'a', 'b', 'c' }) == true)

    local items = c:get(pkg, sid, 'items')
    assert(type(items) == 'table' and #items == 3 and items[1] == 'a' and items[3] == 'c')

    test.expect_error_contains(function()
        c:set(pkg, sid, 'items', {})
    end, 'Cannot set an uci option to an empty table value', 'set should reject empty table for list option')

    assert(c:rename(pkg, sid, 'renamed') == true)

    local v = c:get(pkg, 'renamed', 'foo')
    assert(v == 'new')

    assert(c:reorder(pkg, 'renamed', 0) == true)

    local first_name
    for s in c:each(pkg, 'demo') do
        first_name = s['.name']
        break
    end
    assert(first_name == 'renamed', 'reorder should move renamed section to index 0')

    assert(c:delete(pkg, 'renamed', 'foo') == true)

    local miss_v, miss_err = c:get(pkg, 'renamed', 'foo')
    assert(miss_v == nil and type(miss_err) == 'string')

    assert(c:save(pkg) == true)
    assert(c:commit(pkg) == true)

    assert(c:set(pkg, 's1', 'foo', 'temp') == true)
    assert(c:get(pkg, 's1', 'foo') == 'temp')
    assert(c:revert(pkg, 's1', 'foo') == true)
    assert(c:get(pkg, 's1', 'foo') == 'bar')

    assert(c:unload(pkg) == true)
    assert(c:load(pkg) == true)

    local persisted = c:get(pkg, 'renamed', 'items')
    assert(type(persisted) == 'table' and #persisted == 3)

    local lk, le = c:load('missing_pkg_zzz')
    assert(lk == false and type(le) == 'string')

    local gv, ge = c:get('missing_pkg_zzz', 's', 'o')
    assert(gv == nil and type(ge) == 'string')

    local dk, de = c:delete('missing_pkg_zzz', 's')
    assert(dk == false and type(de) == 'string')

    local ei = c:each('missing_pkg_zzz')
    assert(ei == nil)

    c:close()
    c:close()

    test.expect_error_contains(function()
        c:get_confdir()
    end, 'UCI context closed', 'cursor methods should fail after close')

    -- GC regression: cursor userdata should be collectible.
    do
        local weak = setmetatable({}, { __mode = 'v' })

        do
            local c2 = uci.cursor(confdir, savedir)
            weak.c2 = c2
        end

        test.full_gc()
        assert(weak.c2 == nil, 'cursor userdata should be collectible when unreachable')
    end

    -- Memory leak regression: repeated cursor load/get/close should plateau.
    do
        local function uci_burst(n)
            for _ = 1, n do
                local cx = uci.cursor(confdir, savedir)
                assert(cx:load(pkg) == true)
                assert(cx:get(pkg, 's1', 'foo') == 'bar')
                cx:close()
            end
        end

        local base_mem_kb = test.lua_mem_kb()

        uci_burst(300)
        local after_first_kb = test.lua_mem_kb()

        uci_burst(300)
        local after_second_kb = test.lua_mem_kb()

        local growth_first_kb = after_first_kb - base_mem_kb
        local growth_second_kb = after_second_kb - after_first_kb
        local plateau_limit_kb = math.max(128, growth_first_kb * 0.35)

        assert(growth_first_kb < 8192,
               string.format('unexpectedly large initial uci memory growth: %.2f KB', growth_first_kb))

        assert(growth_second_kb <= plateau_limit_kb,
               string.format('uci memory keeps growing across equal bursts: first %.2f KB, second %.2f KB (limit %.2f KB)',
                             growth_first_kb, growth_second_kb, plateau_limit_kb))
    end
end, debug.traceback)

rm_rf(tmp_base)

assert(ok, err)

print('uci tests passed')
