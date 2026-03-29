#!/usr/bin/env eco

local ok_mod, ubus = pcall(require, 'eco.ubus')
if not ok_mod then
    print('skip ubus tests: ' .. tostring(ubus))
    os.exit(0)
end

local shared = require 'eco.shared'
local eco = require 'eco'
local sys = require 'eco.sys'
local time = require 'eco.time'
local test = require 'test'

local function uniq(tag)
    return string.format('eco.ubus.%s.%d.%d', tag, sys.getpid(), math.floor(time.now() * 1000))
end

local function wait_until(timeout, pred)
    local deadline = time.now() + timeout

    while time.now() < deadline do
        if pred() then
            return true
        end

        eco.sleep(0.01)
    end

    return nil, 'timeout'
end

local function connect_retry(timeout)
    local deadline = time.now() + (timeout or 2.0)
    local con, err

    while time.now() < deadline do
        con, err = ubus.connect()
        if con then
            return con
        end

        time.sleep(0.05)
    end

    return nil, err
end

local shmem_name = string.format('dict-%d', sys.getpid())

local function stop_ubusd()
    test.run_case_async('stop ubusd', function()
        local dict = shared.get(shmem_name)
        if dict then
            dict:set('stop', true)
        end
        eco.sleep(0.1)
    end)
end

eco.set_panic_hook(function(...)
    stop_ubusd()

    for _, v in ipairs({...}) do
        print(v)
    end
end)

test.run_case_sync('Constants/basic API checks', function()
    assert(math.type(ubus.STATUS_OK) == 'integer')
    assert(math.type(ubus.STATUS_INVALID_COMMAND) == 'integer')
    assert(math.type(ubus.STATUS_INVALID_ARGUMENT) == 'integer')
    assert(math.type(ubus.STATUS_METHOD_NOT_FOUND) == 'integer')
    assert(math.type(ubus.STATUS_NOT_FOUND) == 'integer')
    assert(math.type(ubus.STATUS_NO_DATA) == 'integer')
    assert(math.type(ubus.STATUS_PERMISSION_DENIED) == 'integer')
    assert(math.type(ubus.STATUS_TIMEOUT) == 'integer')
    assert(math.type(ubus.STATUS_NOT_SUPPORTED) == 'integer')
    assert(math.type(ubus.STATUS_UNKNOWN_ERROR) == 'integer')
    assert(math.type(ubus.STATUS_CONNECTION_FAILED) == 'integer')

    assert(math.type(ubus.ARRAY) == 'integer')
    assert(math.type(ubus.TABLE) == 'integer')
    assert(math.type(ubus.STRING) == 'integer')
    assert(math.type(ubus.INT64) == 'integer')
    assert(math.type(ubus.INT32) == 'integer')
    assert(math.type(ubus.INT16) == 'integer')
    assert(math.type(ubus.INT8) == 'integer')
    assert(math.type(ubus.DOUBLE) == 'integer')
    assert(math.type(ubus.BOOLEAN) == 'integer')

    local estr = ubus.strerror(ubus.STATUS_OK)
    assert(type(estr) == 'string' and #estr > 0)
end)

sys.spawn(function()
    local dict, err = shared.new(shmem_name, 1024)
    assert(dict, err)

    local ubusd, ubusd_err = sys.exec('ubusd')
    assert(ubusd, ubusd_err)

    while true do
        if dict:get('stop') then
            ubusd:stop()
            eco.unloop()
            break
        end
        eco.sleep(0.01)
    end

    print('ubusd quit')
end)

test.run_case_sync('ubus connection smoke', function()
    eco.run(function()
        local con<close>, cerr = connect_retry(2.0)
        assert(con, string.format('connect failed (%s).', tostring(cerr)))
    end)
end)

test.run_case_sync('ubus call/add/signatures/objects/errors/closed', function()
    eco.run(function()
        local con<close>, cerr = connect_retry(2.0)
        assert(con, cerr)

        local object = uniq('api')
        local obj, aerr = con:add(object, {
            echo = {
                function(req, msg, c)
                    if type(msg.text) ~= 'string' then
                        return ubus.STATUS_INVALID_ARGUMENT
                    end

                    c:reply(req, {
                        text = msg.text,
                        i = msg.i,
                        flag = msg.flag,
                        arr = msg.arr,
                        tab = msg.tab
                    })
                end,
                {
                    text = ubus.STRING,
                    i = ubus.INT32,
                    flag = ubus.BOOLEAN,
                    arr = ubus.ARRAY,
                    tab = ubus.TABLE
                }
            },
            twice = {
                function(req, _, c)
                    c:reply(req, { part = 1 })
                    c:reply(req, { part = 2 })
                end
            },
            nodata = {
                function()
                    return ubus.STATUS_OK
                end
            },
            implicit_ok = {
                function(req, _, c)
                    c:reply(req, { ok = true })
                    return 'ignored'
                end
            },
            fail = {
                function()
                    return ubus.STATUS_INVALID_ARGUMENT
                end
            },
            slow = {
                function(req, _, c)
                    eco.sleep(0.15)
                    c:reply(req, { done = true })
                end
            }
        })
        assert(obj, aerr)

        local _, derr = con:add(object, {})
        assert(derr == 'object exists')

        local sigs, serr = con:signatures(object)
        assert(sigs and serr == nil)
        assert(type(sigs.echo) == 'table')
        assert(sigs.echo.text == ubus.STRING)
        assert(sigs.echo.i == ubus.INT32)

        local objs, oerr = con:objects()
        assert(objs and oerr == nil)
        local found = false
        for _, path in pairs(objs) do
            if path == object then
                found = true
                break
            end
        end
        assert(found, 'added object should be visible in object list')

        local payload = {
            text = 'hello',
            i = 7,
            flag = true,
            arr = { 1, 2, 3 },
            tab = { a = 'b' }
        }

        local res, rerr = con:call(object, 'echo', payload, 1.0)
        assert(res and rerr == nil)
        assert(res.text == 'hello')
        assert(res.i == 7)
        assert(res.flag == true)
        assert(type(res.arr) == 'table' and res.arr[3] == 3)
        assert(type(res.tab) == 'table' and res.tab.a == 'b')

        local p1, p2 = con:call(object, 'twice', {}, 1.0)
        assert(type(p1) == 'table' and type(p2) == 'table')
        assert(p1.part == 1 and p2.part == 2)

        local empty = con:call(object, 'nodata', {}, 1.0)
        assert(type(empty) == 'table' and next(empty) == nil)

        local okmsg, ierr = con:call(object, 'implicit_ok', {}, 1.0)
        assert(okmsg and ierr == nil)
        assert(okmsg.ok == true)

        local _, ferr = con:call(object, 'fail', {}, 1.0)
        assert(type(ferr) == 'string' and ferr:lower():find('invalid', 1, true))

        local _, terr = con:call(object, 'slow', {}, 0.03)
        assert(terr == 'timeout')

        local _, nferr = con:call(uniq('missing_obj'), 'echo', {}, 0.1)
        assert(nferr == 'not found')

        local _, mderr = con:call(object, 'missing_method', {}, 0.2)
        assert(type(mderr) == 'string' and #mderr > 0)

        local _, suberr = con:subscribe(uniq('missing_sub'), function() end)
        assert(suberr == 'not found')

        con:close()
        con:close()

        assert(con:call(object, 'echo', {}, 0.1) == nil)
        assert(con:send('x', {}) == nil)
        assert(con:listen('*', function() end) == nil)
        assert(con:add(uniq('x'), {}) == nil)
        assert(con:subscribe(object, function() end) == nil)
        assert(con:unsubscribe(object) == nil)
        assert(con:notify(obj, 'tick', {}) == nil)
        assert(con:objects() == nil)
        assert(con:signatures(object) == nil)
    end)
end)

test.run_case_sync('ubus listen/send and subscribe/notify', function()
    eco.run(function()
        local recv, rerr = connect_retry(2.0)
        assert(recv, rerr)

        local send, serr = connect_retry(2.0)
        assert(send, serr)

        local ev_name = uniq('event')
        local ev_msg

        local ok_listen, lerr = recv:listen('*', function(ev, msg)
            if ev == ev_name then
                ev_msg = msg
            end
        end)
        assert(ok_listen, lerr)

        local ok_send, se = send:send(ev_name, { n = 42, text = 'ok' })
        assert(ok_send == true, se)

        local wok, werr = wait_until(1.0, function()
            return ev_msg ~= nil
        end)
        assert(wok, werr)
        assert(ev_msg.n == 42 and ev_msg.text == 'ok')

        local pub, perr = connect_retry(2.0)
        assert(pub, perr)

        local sub, suerr = connect_retry(2.0)
        assert(sub, suerr)

        local object = uniq('pub')
        local obj, aerr = pub:add(object, {})
        assert(obj, aerr)

        local got_method, got_msg
        local subh, serr2 = sub:subscribe(object, function(method, msg)
            got_method = method
            got_msg = msg
        end)
        assert(subh, serr2)

        local ok_notify, nerr = pub:notify(obj, 'tick', { seq = 1, flag = true })
        assert(ok_notify, nerr)

        wok, werr = wait_until(1.0, function()
            return got_msg ~= nil
        end)
        assert(wok, werr)
        assert(got_method == 'tick')
        assert(got_msg.seq == 1 and got_msg.flag == true)

        local ok_unsub, uerr = sub:unsubscribe(subh)
        assert(ok_unsub, uerr)

        got_method = nil
        got_msg = nil

        ok_notify, nerr = pub:notify(obj, 'tick', { seq = 2, flag = false })
        assert(ok_notify, nerr)

        eco.sleep(0.1)
        assert(got_method == nil and got_msg == nil,
            'should not receive notifications after unsubscribe')

        local _, nuerr = sub:unsubscribe(subh)
        assert(nuerr == 'not found')

        sub:close()
        pub:close()
        send:close()
        recv:close()
    end)
end)

test.run_case_sync('ubus one-shot helpers use default socket', function()
    eco.run(function()
        local con<close>, cerr = connect_retry(2.0)
        assert(con, cerr)

        local object = uniq('oneshot')
        local _, aerr = con:add(object, {
            echo = {
                function(req, msg, c)
                    c:reply(req, msg)
                end,
                { text = ubus.STRING }
            },
            fail = {
                function()
                    return ubus.STATUS_NOT_SUPPORTED
                end
            }
        })
        assert(aerr == nil)

        local event = uniq('oneshot_event')
        local got

        local ok_listen, lerr = con:listen('*', function(ev, msg)
            if ev == event then
                got = msg
            end
        end)
        assert(ok_listen, lerr)

        local objs, oerr = ubus.objects()
        assert(objs and oerr == nil)

        local found = false
        for _, path in pairs(objs) do
            if path == object then
                found = true
                break
            end
        end
        assert(found)

        local sigs, serr = ubus.signatures(object)
        assert(sigs and serr == nil)
        assert(type(sigs.echo) == 'table' and sigs.echo.text == ubus.STRING)

        local res, rerr = ubus.call(object, 'echo', { text = 'oneshot' }, 1.0)
        assert(res and rerr == nil)
        assert(res.text == 'oneshot')

        local _, ferr = ubus.call(object, 'fail', {}, 1.0)
        assert(type(ferr) == 'string' and #ferr > 0)

        local ok_send, send_err = ubus.send(event, { ok = true })
        assert(ok_send == true and send_err == nil)

        local wok, werr = wait_until(1.0, function()
            return got ~= nil
        end)
        assert(wok, werr)
        assert(got.ok == true)
    end)
end)

test.run_case_sync('ubus stress concurrent call throughput', function()
    eco.run(function()
        local workers = 8
        local loops = 80
        local done = 0
        local ok_calls = 0

        local srv<close>, serr = connect_retry(2.0)
        assert(srv, serr)

        local object = uniq('stress')
        local _, aerr = srv:add(object, {
            echo = {
                function(req, msg, c)
                    c:reply(req, { v = msg.v })
                end,
                { v = ubus.INT32 }
            }
        })
        assert(aerr == nil)

        for w = 1, workers do
            eco.run(function()
                local cli, cerr = connect_retry(2.0)
                assert(cli, cerr)

                for i = 1, loops do
                    local v = w * 100000 + i
                    local res, rerr = cli:call(object, 'echo', { v = v }, 1.0)
                    assert(res and rerr == nil)
                    assert(res.v == v)
                    ok_calls = ok_calls + 1
                end

                cli:close()
                done = done + 1
            end)
        end

        local wok, werr = wait_until(20.0, function()
            return done == workers
        end)
        assert(wok, werr)
        assert(ok_calls == workers * loops)
    end)
end)

test.run_case_sync('ubus memory leak regression plateau', function()
    local function burst(rounds, per_round)
        for r = 1, rounds do
            local srv, serr = connect_retry(2.0)
            assert(srv, serr)

            local object = uniq('mem' .. r)
            local _, aerr = srv:add(object, {
                echo = {
                    function(req, msg, c)
                        c:reply(req, msg)
                    end,
                    { i = ubus.INT32, s = ubus.STRING }
                }
            })
            assert(aerr == nil)

            local cli, cerr = connect_retry(2.0)
            assert(cli, cerr)

            for i = 1, per_round do
                local res, rerr = cli:call(object, 'echo', { i = i, s = 'x' }, 1.0)
                assert(res and rerr == nil)
                assert(res.i == i and res.s == 'x')
            end

            cli:close()
            srv:close()
        end
    end

    eco.run(function()
        local rounds = 4
        local per_round = 60

        local base_mem_kb = test.lua_mem_kb()

        burst(rounds, per_round)
        local after_first_kb = test.lua_mem_kb()

        burst(rounds, per_round)
        local after_second_kb = test.lua_mem_kb()

        local growth_first_kb = after_first_kb - base_mem_kb
        local growth_second_kb = after_second_kb - after_first_kb
        local plateau_limit_kb = math.max(256, growth_first_kb * 0.50)

        assert(growth_first_kb < 12288,
                string.format('unexpectedly large initial ubus memory growth: %.2f KB', growth_first_kb))

        assert(growth_second_kb <= plateau_limit_kb,
                string.format('ubus memory keeps growing across equal bursts: first %.2f KB, second %.2f KB (limit %.2f KB)',
                                growth_first_kb, growth_second_kb, plateau_limit_kb))
    end)
end)

stop_ubusd()

print('ubus tests passed')
