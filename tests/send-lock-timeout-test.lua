#!/usr/bin/env eco

local socket = require 'eco.socket'
local ssl = require 'eco.ssl'
local time = require 'eco.time'
local test = require 'test'

local path = os.tmpname()
do
    local f<close> = assert(io.open(path, 'wb'))
    assert(f:write('payload'))
end

local server = assert(ssl.listen('127.0.0.1', 0, {
    cert = 'cert.pem', key = 'key.pem', insecure = true
}))
local addr = assert(server.sock:getsockname())
local peer

eco.run(function()
    peer = assert(server:accept())
end)

local tls = assert(ssl.connect('127.0.0.1', addr.port, { insecure = true }))
test.wait_until('TLS peer ready', function() return peer ~= nil end)

local tcp = assert(socket.tcp())

for _, client in ipairs({ tcp, tls }) do
    local writer = client.wr

    for _, method in ipairs({ 'send', 'sendfile' }) do
        local calls = 0
        local write

        -- Keep real mutex scheduling, while observing the writer's time budget.
        client.wr = {
            write = function(_, data, timeout)
                calls = calls + 1
                return write(#data, timeout)
            end,
            sendfile = function(_, name, offset, len, timeout)
                calls = calls + 1
                return write(len, timeout)
            end
        }

        local function send(timeout)
            if method == 'sendfile' then
                return client:sendfile(path, 7, nil, timeout)
            end

            return client:send('payload', timeout)
        end

        assert(client.mutex:lock())
        write = function() error('writer entered without acquiring the lock') end

        local sent, err = send(0.02)
        assert(sent == nil and err == 'timeout', tostring(err))
        assert(calls == 0 and client.mutex.locked, 'timeout must not release another owner')
        client.mutex:unlock()

        assert(client.mutex:lock())
        eco.run(function()
            eco.sleep(0.04)
            client.mutex:unlock()
        end)

        write = function(len, timeout)
            assert(timeout > 0 and timeout < 0.08, 'lock wait was not deducted')
            eco.sleep(timeout)
            return nil, 'timeout'
        end

        sent, err = send(0.1)
        assert(sent == nil and err == 'timeout', tostring(err))
        assert(not client.mutex.locked, 'write failure must release the lock')

        for _, timeout in ipairs({ false, 0, -1 }) do
            assert(client.mutex:lock())
            eco.run(function()
                eco.sleep(0.01)
                client.mutex:unlock()
            end)

            write = function(len, remaining)
                assert(remaining == nil, 'nonpositive timeout must remain unlimited')
                return len
            end

            assert(send(timeout or nil) == 7)
            assert(not client.mutex.locked)
        end

        -- Budget can expire after lock handoff but before the sender resumes.
        local now = time.now
        local reads = 0
        time.now = function(clock)
            assert(clock == time.CLOCK_MONOTONIC)
            reads = reads + 1
            return reads
        end

        local before = calls
        sent, err = send(0.1)
        time.now = now

        assert(sent == nil and err == 'timeout', tostring(err))
        assert(calls == before and not client.mutex.locked)
    end

    client.wr = writer
    client:close()
end

peer:close()
server:close()
assert(os.remove(path))
print('socket/TLS send lock timeout tests passed')
