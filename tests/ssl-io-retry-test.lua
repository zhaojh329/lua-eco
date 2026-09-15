#!/usr/bin/env eco

-- Build ssl_io_retry.so as described in ssl-io-retry.c before running.
local ssl = require 'ssl_io_retry'
local socket = require 'eco.socket'
local test = require 'test'
local time = require 'eco.time'

local function with_session(fn)
    local a, b = socket.socketpair(socket.AF_UNIX, socket.SOCK_STREAM)
    assert(a and b)

    local ctx = ssl.context()
    local session = assert(ctx:new(a:getfd(), true))
    local rd = eco.reader(a:getfd(), ssl.read, session:pointer())
    local wr = eco.writer(a:getfd(), ssl.write, session:pointer())

    fn(rd, wr, a, b)

    session:free()
    ctx:free()
    a:close()
    b:close()
end

with_session(function(rd)
    ssl.configure(ssl.WANT_WRITE, 1)

    local data, err = rd:readfull(1, 0.2)
    assert(data == 'x', err)
    assert(ssl.call_count() == 2)
end)

with_session(function(rd, wr, a, b)
    ssl.configure(ssl.WANT_READ, 1)

    eco.run(function()
        eco.sleep(0.03)
        assert(b:send('ready') == 5)
    end)

    local started = time.now()
    local sent, err = wr:write('payload', 0.2)
    assert(sent == 7, err)
    assert(time.now() - started >= 0.02, 'write resumed before read readiness')
    assert(ssl.call_count() == 2)
end)

with_session(function(rd, wr)
    ssl.configure(ssl.WANT_READ, 1000)

    local sent, err = wr:write('payload', 0.03)
    assert(sent == nil and err == 'timeout', tostring(err))
    assert(ssl.call_count() == 1, 'write retried without read readiness')
end)

with_session(function(rd, wr)
    ssl.configure(ssl.WANT_READ, 1000)

    eco.run(function()
        eco.sleep(0.01)
        wr:cancel()
    end)

    local sent, err = wr:write('payload', 0.2)
    assert(sent == nil and err == 'canceled', tostring(err))
    assert(ssl.call_count() == 1)
end)

with_session(function(rd, wr, a)
    local sent, err = a:send(string.rep('x', 1024 * 1024), 0.01)
    assert(sent == nil and err == 'timeout', 'send buffer must be full')
    ssl.configure(ssl.WANT_WRITE, 1000)

    local data
    data, err = rd:readfull(1, 0.03)
    assert(data == nil and err == 'timeout', tostring(err))
    assert(ssl.call_count() == 1)

    eco.run(function()
        eco.sleep(0.01)
        rd:cancel()
    end)

    data, err = rd:readfull(1, 0.2)
    assert(data == nil and err == 'canceled', tostring(err))
    assert(ssl.call_count() == 2)
end)

with_session(function(rd, wr, a, b)
    local waiting = false
    local done = false

    eco.run(function()
        waiting = true
        assert(a:readfull(1, 0.2) == 'r')
        done = true
    end)

    test.wait_until('reader waits', function() return waiting end)
    ssl.configure(ssl.WANT_READ, 1)

    local sent, err = wr:write('payload', 0.2)
    assert(sent == nil and type(err) == 'string', 'direction conflict must fail')

    assert(b:send('r') == 1)
    test.wait_until('original reader survives direction conflict', function() return done end)

    ssl.configure(ssl.WANT_WRITE, 1)
    assert(wr:write('payload', 0.2) == 7, 'writer must remain usable after conflict')
end)

with_session(function(rd, wr, a, b)
    local sent, err = a:send(string.rep('x', 1024 * 1024), 0.01)
    assert(sent == nil and err == 'timeout', 'send buffer must be full')

    local waiting = false
    local done = false
    local waiter = eco.writer(a:getfd())

    eco.run(function()
        waiting = true
        assert(waiter:wait(0.2))
        done = true
    end)

    test.wait_until('writer waits', function() return waiting end)
    ssl.configure(ssl.WANT_WRITE, 1)

    local data
    data, err = rd:readfull(1, 0.2)
    assert(data == nil and type(err) == 'string', 'direction conflict must fail')

    while b:read(1024 * 1024, 0.01) do end
    test.wait_until('original writer survives direction conflict', function() return done end)

    ssl.configure(ssl.WANT_READ, 1)
    assert(b:send('r') == 1)
    assert(rd:readfull(1, 0.2) == 'x', 'reader must remain usable after conflict')
end)

print('ssl I/O retry direction tests passed')
