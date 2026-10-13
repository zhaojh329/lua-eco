#!/usr/bin/env eco

local socket = require 'eco.socket'
local eco = require 'eco'
local test = require 'test'

test.run_case_sync('datagram reads preserve packet boundaries without a reader', function()
    local a, b = assert(socket.socketpair(socket.AF_UNIX, socket.SOCK_DGRAM,
                                        nil, { read_buffer_size = 512 }))
    assert(a.rd == nil and b.rd == nil)

    local payload = string.rep('x', 8192)
    assert(a:send(payload) == #payload)
    assert(b:read(#payload, 0.5) == payload)

    assert(a:send('abcdef') == 6)
    assert(a:send('next') == 4)
    assert(b:recv(2, 0.5) == 'ab')
    assert(b:recvfrom(64, 0.5) == 'next')

    assert(a:send('short') == 5)
    assert(a:send('tail') == 4)
    local result = table.pack(b:recv(64, 0.5))
    assert(result.n == 1 and result[1] == 'short')
    assert(b:read(64, 0.5) == 'tail')

    for _, format in ipairs({'l', 'L', 'a', 1.0, 1.5}) do
        test.expect_error_contains(function()
            b:read(format, 0.01)
        end, 'datagram read size')
    end

    assert(a:send('pending') == 7)

    for _, name in ipairs({'read', 'recvfrom'}) do
        for _, size in ipairs({0, -1, 0x80000000, 0x100000001, math.maxinteger}) do
            test.expect_error_contains(function()
                b[name](b, size, 0.5)
            end, 'size out of range')
        end
    end

    assert(b:read(64, 0.5) == 'pending', 'invalid sizes must not consume a packet')

    for _, name in ipairs({'readfull', 'recvfull', 'readuntil'}) do
        test.expect_error_contains(function()
            b[name](b, 1, 0.01)
        end, 'requires a stream socket')
    end

    a:close()
    b:close()
end)

test.run_case_sync('UDP generic receive handles empty packets and timeouts', function()
    local server<close> = assert(socket.listen_udp('127.0.0.1', 0))
    local addr = assert(server:getsockname())
    local client<close> = assert(socket.connect_udp('127.0.0.1', addr.port))
    assert(server.rd == nil and client.rd == nil)

    -- Send an actual empty packet; the public send helpers skip empty writes.
    assert(client.sock:sendto('', '127.0.0.1', addr.port) == 0)
    assert(server:recv(64, 0.5) == '')

    local payload = string.rep('u', 1024)
    assert(client:send(payload) == #payload)
    local data, peer = server:recvfrom(4096, 0.5)
    assert(data == payload and peer.ipaddr == '127.0.0.1')
    assert(server:sendto('reply', peer.ipaddr, peer.port) == 5)
    assert(client:recv(64, 0.5) == 'reply')

    for _, name in ipairs({'recv', 'recvfrom'}) do
        local none, err = server[name](server, 64, 0.01)
        assert(none == nil and err == 'timeout')
    end
end)

for _, name in ipairs({'recv', 'recvfrom'}) do
    test.run_case_sync('close cancels datagram ' .. name, function()
        local server = assert(socket.listen_udp('127.0.0.1', 0))
        local done = false

        eco.run(function()
            local data, err = server[name](server, 64, 1.0)
            assert(data == nil and err == 'canceled')
            done = true
        end)

        server:close()
        assert(not done, 'close must not resume a waiter synchronously')
        test.wait_until('datagram cancellation', function() return done end, 0.5)
    end)
end

test.run_case_sync('netlink raw socket receives without a reader', function()
    local sock<close> = assert(socket.netlink(0))
    assert(sock.rd == nil)
    assert(sock:bind())

    -- RTM_GETLINK with NLM_F_REQUEST | NLM_F_DUMP and an empty ifinfomsg.
    local request = string.pack('=I4I2I2I4I4', 32, 18, 0x301, 1, 0)
        .. string.rep('\0', 16)
    assert(sock:sendto(request, 0, 0) == #request)
    local reply = assert(sock:recv(65536, 1.0))
    assert(#reply >= 16 and string.unpack('=I4', reply) <= #reply)
end)

print('socket datagram tests passed')
