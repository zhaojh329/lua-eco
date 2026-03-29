#!/usr/bin/env eco

local ssl = require 'eco.ssl'
local file = require 'eco.file'
local eco = require 'eco'
local sys = require 'eco.sys'
local time = require 'eco.time'
local test = require 'test'

local function run_case(name, fn)
    test.run_case_async(name, fn)
end

local function cert_paths()
    local cert = 'cert.pem'
    local key = 'key.pem'

    if not file.access(cert) then
        cert = 'tests/cert.pem'
        key = 'tests/key.pem'
    end

    assert(file.access(cert), 'cert file not found')
    assert(file.access(key), 'key file not found')

    return cert, key
end

local cert, key = cert_paths()

assert(math.type(ssl.OK) == 'integer')
assert(math.type(ssl.ERROR) == 'integer')
assert(math.type(ssl.WANT_READ) == 'integer')
assert(math.type(ssl.WANT_WRITE) == 'integer')
assert(math.type(ssl.INSECURE) == 'integer')

run_case('ssl listen/connect echo', function()
    local server, err = ssl.listen('127.0.0.1', 0, {
        reuseaddr = true,
        cert = cert,
        key = key,
        insecure = true
    })
    assert(server, err)

    local addr = assert(server.sock:getsockname())
    assert(addr.port > 0)

    eco.run(function()
        local c, peer = server:accept()
        assert(c, peer)
        assert(type(peer) == 'table')

        local data, rerr = c:readfull(5, 2.0)
        assert(data == 'hello', rerr)

        local n, serr = c:send('world', 2.0)
        assert(n == 5, serr)

        c:close()
        server:close()
    end)

    eco.run(function()
        local cli, cerr = ssl.connect('127.0.0.1', addr.port, { insecure = true })
        assert(cli, cerr)

        local n, serr = cli:send('hello', 2.0)
        assert(n == 5, serr)

        local data, rerr = cli:readfull(5, 2.0)
        assert(data == 'world', rerr)

        cli:close()
    end)
end)

run_case('ssl readuntil and sendfile', function()
    local path = string.format('/tmp/eco-ssl-sendfile-%d-%d', sys.getpid(), math.floor(time.now() * 1000))
    local f = assert(io.open(path, 'wb'))
    f:write('0123456789')
    f:close()

    local server, err = ssl.listen('127.0.0.1', 0, {
        reuseaddr = true,
        cert = cert,
        key = key,
        insecure = true
    })
    assert(server, err)

    local addr = assert(server.sock:getsockname())

    eco.run(function()
        local c, peer = server:accept()
        assert(c, peer)

        local chunk, found = c:readuntil('END', 2.0)
        assert(chunk == 'abc')
        assert(found == true)

        local tail, terr = c:readfull(4, 2.0)
        assert(tail == 'tail', terr)

        local sf, serr = c:readfull(5, 2.0)
        assert(sf == '23456', serr)

        local n, aerr = c:send('ok', 2.0)
        assert(n == 2, aerr)

        c:close()
        server:close()
    end)

    eco.run(function()
        local cli, cerr = ssl.connect('127.0.0.1', addr.port, { insecure = true })
        assert(cli, cerr)

        local n, serr = cli:send('abcENDtail', 2.0)
        assert(n == 10, serr)

        n, serr = cli:sendfile(path, 5, 2, 2.0)
        assert(n == 5, serr)

        local okmsg, rerr = cli:readfull(2, 2.0)
        assert(okmsg == 'ok', rerr)

        cli:close()
        os.remove(path)
    end)
end)

run_case('ssl client custom ctx', function()
    local ctx = ssl.context()

    local server, err = ssl.listen('127.0.0.1', 0, {
        reuseaddr = true,
        cert = cert,
        key = key,
        insecure = true
    })
    assert(server, err)

    local addr = assert(server.sock:getsockname())

    eco.run(function()
        local c, peer = server:accept()
        assert(c, peer)

        local msg, rerr = c:readfull(1, 2.0)
        assert(msg == '1', rerr)

        local n, serr = c:send('K', 2.0)
        assert(n == 1, serr)

        c:close()

        server:close()
    end)

    eco.run(function()
        local cli, cerr = ssl.connect('127.0.0.1', addr.port, {
            insecure = true,
            ctx = ctx
        })
        assert(cli, cerr)

        local n, serr = cli:send('1', 2.0)
        assert(n == 1, serr)

        local ack, rerr = cli:readfull(1, 2.0)
        assert(ack == 'K', rerr)

        cli:close()
    end)

end)

run_case('ssl close cancels pending read', function()
    local server, err = ssl.listen('127.0.0.1', 0, {
        reuseaddr = true,
        cert = cert,
        key = key,
        insecure = true
    })
    assert(server, err)

    local addr = assert(server.sock:getsockname())

    eco.run(function()
        local c, peer = server:accept()
        assert(c, peer)

        eco.sleep(0.2)

        c:close()
        server:close()
    end)

    eco.run(function()
        local cli, cerr = ssl.connect('127.0.0.1', addr.port, { insecure = true })
        assert(cli, cerr)

        eco.run(function()
            local data, rerr = cli:readfull(1, 5.0)
            assert(data == nil and rerr == 'canceled',
                   string.format('pending read should be canceled by close, got data=%s err=%s', tostring(data), tostring(rerr)))
        end)

        eco.run(function()
            eco.sleep(0.05)
            cli:close()
        end)
    end)
end)

run_case('ssl context free blocks new sessions', function()
    local ctx = ssl.context()

    ctx:free()

    local ssock, err = ctx:new(0, true)
    assert(ssock == nil and err == 'context closed')
end)

run_case('ssl context free idempotent with active session', function()
    local ctx = ssl.context()

    local server, err = ssl.listen('127.0.0.1', 0, {
        reuseaddr = true,
        cert = cert,
        key = key,
        insecure = true
    })
    assert(server, err)

    local addr = assert(server.sock:getsockname())

    eco.run(function()
        local c, peer = server:accept()
        assert(c, peer)

        local msg, rerr = c:readfull(1, 2.0)
        assert(msg == 'z', rerr)

        local n, serr = c:send('Y', 2.0)
        assert(n == 1, serr)

        c:close()
        server:close()
    end)

    eco.run(function()
        local cli, cerr = ssl.connect('127.0.0.1', addr.port, {
            insecure = true,
            ctx = ctx
        })
        assert(cli, cerr)

        ctx:free()
        ctx:free()

        local ssock, nerr = ctx:new(0, true)
        assert(ssock == nil and nerr == 'context closed')

        local n, serr = cli:send('z', 2.0)
        assert(n == 1, serr)

        local ack, rerr = cli:readfull(1, 2.0)
        assert(ack == 'Y', rerr)

        cli:close()
    end)
end)

run_case('ssl option load failures', function()
    local s, err = ssl.listen('127.0.0.1', 0, {
        cert = '/tmp/__no_such_cert__.pem',
        key = key,
        insecure = true
    })
    assert(s == nil and err == 'load cert file fail')

    s, err = ssl.listen('127.0.0.1', 0, {
        cert = cert,
        key = '/tmp/__no_such_key__.pem',
        insecure = true
    })
    assert(s == nil and err == 'load key file fail')

    local server, serr = ssl.listen('127.0.0.1', 0, {
        cert = cert,
        key = key,
        insecure = true
    })
    assert(server, serr)

    local addr = assert(server.sock:getsockname())

    eco.run(function()
        local cli, cerr = ssl.connect('127.0.0.1', addr.port, {
            ca = '/tmp/__no_such_ca__.pem',
            insecure = true
        })
        assert(cli == nil and cerr == 'load ca file fail')

        server:close()
    end)
end)

-- GC regression: ssl client wrapper should be collectible and close underlying fd.
do
    local weak = setmetatable({}, { __mode = 'v' })
    local fd

    run_case('ssl client gc closes fd', function()
        local server, err = ssl.listen('127.0.0.1', 0, {
            cert = cert,
            key = key,
            insecure = true,
            reuseaddr = true
        })
        assert(server, err)

        local addr = assert(server.sock:getsockname())

        eco.run(function()
            local c, peer = server:accept()
            assert(c, peer)

            local msg, rerr = c:readfull(1, 2.0)
            assert(msg == 'x', rerr)

            c:close()
            server:close()
        end)

        eco.run(function()
            local cli, cerr = ssl.connect('127.0.0.1', addr.port, { insecure = true })
            assert(cli, cerr)

            fd = cli.sock:getfd()
            weak.cli = cli

            local n, serr = cli:send('x', 2.0)
            assert(n == 1, serr)
        end)
    end)

    test.full_gc()
    assert(weak.cli == nil, 'ssl client object should be collectible when unreachable')

    local ok, err = file.close(fd)
    assert(ok == nil and type(err) == 'string', 'ssl client fd should be closed by GC path')
end

-- Memory leak regression: repeated ssl handshake/read/write should plateau.
do
    local function ssl_burst(n)
        local server, err = ssl.listen('127.0.0.1', 0, {
            reuseaddr = true,
            cert = cert,
            key = key,
            insecure = true
        })
        assert(server, err)

        local addr = assert(server.sock:getsockname())
        local served = 0

        eco.run(function()
            for _ = 1, n do
                local c, peer = server:accept()
                assert(c, peer)

                local msg, rerr = c:readfull(4, 2.0)
                assert(msg == 'ping', rerr)

                local sent, serr = c:send('pong', 2.0)
                assert(sent == 4, serr)

                c:close()
                served = served + 1
            end

            server:close()
        end)

        eco.run(function()
            for _ = 1, n do
                local cli, cerr = ssl.connect('127.0.0.1', addr.port, { insecure = true })
                assert(cli, cerr)

                local sent, serr = cli:send('ping', 2.0)
                assert(sent == 4, serr)

                local msg, rerr = cli:readfull(4, 2.0)
                assert(msg == 'pong', rerr)

                cli:close()
            end
        end)

        test.wait_until('ssl burst completes', function()
            return served == n
        end, 5.0)
        assert(served == n)
    end

    local base_mem_kb = test.lua_mem_kb()

    ssl_burst(40)
    local after_first_kb = test.lua_mem_kb()

    ssl_burst(40)
    local after_second_kb = test.lua_mem_kb()

    local growth_first_kb = after_first_kb - base_mem_kb
    local growth_second_kb = after_second_kb - after_first_kb
    local plateau_limit_kb = math.max(128, growth_first_kb * 0.35)

    assert(growth_first_kb < 8192,
           string.format('unexpectedly large initial ssl memory growth: %.2f KB', growth_first_kb))

    assert(growth_second_kb <= plateau_limit_kb,
           string.format('ssl memory keeps growing across equal bursts: first %.2f KB, second %.2f KB (limit %.2f KB)',
                         growth_first_kb, growth_second_kb, plateau_limit_kb))
end

print('ssl tests passed')
