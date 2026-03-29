#!/usr/bin/env eco

local socket = require 'eco.socket'
local file = require 'eco.file'
local time = require 'eco.time'
local sys = require 'eco.sys'
local eco = require 'eco'

local test = require 'test'

local function tmp_unix_path(tag)
    return string.format('/tmp/eco-socket-test-%s-%d-%d.sock', tag, sys.getpid(), math.floor(time.now() * 1000))
end

local function remove_unix_path(path)
    if path and file.access(path) then
        os.remove(path)
    end
end

-- Constants and address helpers.
assert(math.type(socket.AF_INET) == 'integer')
assert(math.type(socket.AF_INET6) == 'integer')
assert(math.type(socket.AF_UNIX) == 'integer')
assert(math.type(socket.SOCK_STREAM) == 'integer')
assert(math.type(socket.SOCK_DGRAM) == 'integer')
assert(math.type(socket.IPPROTO_TCP) == 'integer')
assert(math.type(socket.IPPROTO_UDP) == 'integer')

assert(socket.is_ip_address('127.0.0.1'))
assert(socket.is_ip_address('::1'))
assert(not socket.is_ip_address('not-an-ip'))

local aton = socket.inet_aton('127.0.0.1')
assert(math.type(aton) == 'integer')
assert(socket.inet_ntoa(aton) == '127.0.0.1')

local pton4 = socket.inet_pton(socket.AF_INET, '127.0.0.1')
assert(type(pton4) == 'string')
assert(socket.inet_ntop(socket.AF_INET, pton4) == '127.0.0.1')

local pton6 = socket.inet_pton(socket.AF_INET6, '::1')
assert(type(pton6) == 'string')
assert(socket.inet_ntop(socket.AF_INET6, pton6) == '::1')

assert(socket.ntohl(socket.htonl(0x12345678)) == 0x12345678)
assert(socket.ntohs(socket.htons(0x1234)) == 0x1234)

local lo = socket.if_nametoindex('lo')
if lo then
    assert(type(socket.if_indextoname(lo)) == 'string')
end

test.expect_error(function()
    socket.connect_tcp('not-an-ip', 80)
end, 'connect_tcp should reject invalid ip string')

test.expect_error(function()
    socket.connect_udp('not-an-ip', 53)
end, 'connect_udp should reject invalid ip string')

test.run_case_sync('socketpair stream read/write/readuntil/sendfile', function()
    local a, b = socket.socketpair(socket.AF_UNIX, socket.SOCK_STREAM)
    assert(a and b, b)

    local path = string.format('/tmp/eco-socket-sendfile-%d-%d', sys.getpid(), math.floor(time.now() * 1000))
    local f = assert(io.open(path, 'wb'))
    f:write('0123456789')
    f:close()

    eco.run(function()
        local chunk, found = b:readuntil('END', 0.5)
        assert(chunk == 'abc')
        assert(found == true)

        local tail, err = b:readfull(4, 0.5)
        assert(tail == 'tail', err)

        local sf, ferr = b:readfull(4, 0.5)
        assert(sf == '3456', ferr)

        b:close()
    end)

    eco.run(function()
        local n, err = a:send('abcENDtail', 0.5)
        assert(n == 10, err)

        n, err = a:sendfile(path, 4, 3)
        assert(n == 4, err)

        a:close()
        os.remove(path)
    end)
end)

test.run_case_sync('socketpair dgram and close state', function()
    local a, b = socket.socketpair(socket.AF_UNIX, socket.SOCK_DGRAM)
    assert(a and b, b)

    eco.run(function()
        local n, err = a:send('ping', 0.2)
        assert(n == 4, err)

        a:close()
        assert(a:closed() == true)

        local n2, e2 = a:send('x', 0.05)
        assert(n2 == nil and type(e2) == 'string', 'send on closed socket should fail')
    end)

    eco.run(function()
        local data, err = b:read(4, 0.5)
        assert(data == 'ping', err)

        b:close()
        assert(b:closed() == true)
    end)
end)

test.run_case_sync('udp sendto recvfrom timeout', function()
    local server, err = socket.listen_udp('127.0.0.1', 0)
    assert(server, err)

    local sinfo = assert(server:getsockname())
    local client, cerr = socket.udp()
    assert(client, cerr)

    eco.run(function()
        local n, e = client:sendto('hello', '127.0.0.1', sinfo.port)
        assert(n == 5, e)
    end)

    eco.run(function()
        local data, peer = server:recvfrom(64, 0.5)
        assert(data == 'hello', peer)
        assert(type(peer) == 'table' and peer.ipaddr == '127.0.0.1')

        local none, terr = server:recvfrom(64, 0.03)
        assert(none == nil and terr == 'timeout')

        server:close()
        client:close()
    end)
end)

test.run_case_sync('tcp listen connect accept peer io', function()
    local server, err = socket.listen_tcp('127.0.0.1', 0, { reuseaddr = true })
    assert(server, err)

    local saddr = assert(server:getsockname())
    assert(saddr.port > 0)

    eco.run(function()
        local c, peer = server:accept()
        assert(c, peer)
        assert(type(peer) == 'table')

        local msg, rerr = c:readfull(5, 1.0)
        assert(msg == 'hello', rerr)

        local n, serr = c:send('world', 1.0)
        assert(n == 5, serr)

        c:close()
        server:close()
    end)

    eco.run(function()
        local cli, cerr = socket.connect_tcp('127.0.0.1', saddr.port)
        assert(cli, cerr)

        local peer = assert(cli:getpeername())
        assert(peer.port == saddr.port)

        local n, serr = cli:send('hello', 1.0)
        assert(n == 5, serr)

        local resp, rerr = cli:readfull(5, 1.0)
        assert(resp == 'world', rerr)

        cli:close()
    end)
end)

local unix_path = tmp_unix_path('listen')
remove_unix_path(unix_path)

test.run_case_sync('unix listen connect and auto unlink on close', function()
    local server, err = socket.listen_unix(unix_path)
    assert(server, err)
    assert(file.access(unix_path), 'unix socket path should exist after listen')

    eco.run(function()
        local c, peer = server:accept()
        assert(c, peer)
        assert(type(peer) == 'table')

        local msg, rerr = c:readfull(4, 1.0)
        assert(msg == 'ping', rerr)

        local n, serr = c:send('pong', 1.0)
        assert(n == 4, serr)

        c:close()
        server:close()
    end)

    eco.run(function()
        local cli, cerr = socket.connect_unix(unix_path)
        assert(cli, cerr)

        local n, serr = cli:send('ping', 1.0)
        assert(n == 4, serr)

        local msg, rerr = cli:readfull(4, 1.0)
        assert(msg == 'pong', rerr)

        cli:close()
    end)
end)

assert(not file.access(unix_path), 'unix socket path should be removed after server close')

test.run_case_sync('options and option errors', function()
    local s, err = socket.tcp()
    assert(s, err)

    assert(s:setoption('keepalive', true))
    assert(s:setoption('tcp_nodelay', true))

    test.expect_error(function()
        s:setoption('no_such_option', true)
    end, 'setoption should reject unsupported option')

    s:close()
end)

test.run_case_sync('socketpair one writer one reader stress', function()
    local s1, s2 = assert(socket.socketpair(socket.AF_UNIX, socket.SOCK_STREAM))
    local loops = 4000
    local payload = string.rep('x', 1024 * 100)
    local total_bytes = loops * #payload
    local wrote_bytes = 0
    local read_bytes = 0
    local write_done = false
    local read_done = false

    s1:setoption('sndbuf', 4096)

    eco.run(function()
        for _ = 1, loops do
            local n, err = s1:send(payload, 2.0)
            assert(n == #payload, err)
            wrote_bytes = wrote_bytes + n
        end

        s1:close()
        write_done = true
    end)

    eco.run(function()
        for _ = 1, loops do
            local data, err = s2:readfull(#payload, 2.0)
            assert(data == payload, err)
            read_bytes = read_bytes + #data
        end

        s2:close()
        read_done = true
    end)

    eco.run(function()
        test.wait_until('writer/reader stress coroutines did not complete in time', function()
            return write_done and read_done
        end, 5.0, 0.01)

        assert(write_done and read_done, 'writer/reader stress coroutines did not complete in time')
        assert(wrote_bytes == total_bytes, 'writer should send expected total bytes')
        assert(read_bytes == total_bytes, 'reader should receive expected total bytes')
    end)
end)

-- GC regression: unreachable socket wrappers should be collectible and close fd.
do
    local weak = setmetatable({}, { __mode = 'v' })
    local fd1, fd2

    do
        local s1, s2 = assert(socket.socketpair(socket.AF_UNIX, socket.SOCK_STREAM))
        fd1 = s1:getfd()
        fd2 = s2:getfd()

        weak.s1 = s1
        weak.s2 = s2
    end

    test.full_gc()

    assert(weak.s1 == nil and weak.s2 == nil,
           'socket wrappers should be collectible after references are dropped')

    local ok, err = file.close(fd1)
    assert(ok == nil and type(err) == 'string', 'fd1 should be closed by GC path')

    ok, err = file.close(fd2)
    assert(ok == nil and type(err) == 'string', 'fd2 should be closed by GC path')
end

-- Memory leak regression: repeated socket bursts should plateau.
do
    local function burst(rounds, n)
        local done = 0

        for r = 1, rounds do
            local round_done_target = done + n

            for i = 1, n do
                local s1, s2 = assert(socket.socketpair(socket.AF_UNIX, socket.SOCK_STREAM))
                local payload = string.format('p-%d-%d', r, i)

                eco.run(function()
                    local n1, e1 = s1:send(payload, 0.5)
                    assert(n1 == #payload, e1)

                    local data, e2 = s2:readfull(#payload, 0.5)
                    assert(data == payload, e2)

                    s1:close()
                    s2:close()
                    done = done + 1
                end)
            end

            test.wait_until('socket burst round completes', function()
                return done == round_done_target
            end, 5.0)
        end
    end

    local rounds = 5
    local n = 600
    local base_mem_kb = test.lua_mem_kb()

    burst(rounds, n)
    local after_first_kb = test.lua_mem_kb()

    burst(rounds, n)
    local after_second_kb = test.lua_mem_kb()

    local growth_first_kb = after_first_kb - base_mem_kb
    local growth_second_kb = after_second_kb - after_first_kb
    local plateau_limit_kb = math.max(128, growth_first_kb * 0.30)

    assert(growth_first_kb < 8192,
           string.format('unexpectedly large initial socket memory growth: %.2f KB', growth_first_kb))

    assert(growth_second_kb <= plateau_limit_kb,
           string.format('socket memory keeps growing across equal bursts: first %.2f KB, second %.2f KB (limit %.2f KB)',
                         growth_first_kb, growth_second_kb, plateau_limit_kb))
end

print('socket tests passed')
