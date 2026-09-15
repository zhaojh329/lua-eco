#!/usr/bin/env eco

local ssl = require 'eco.ssl'
local socket = require 'eco.socket'
local time = require 'eco.time'

local server<close> = assert(socket.listen_tcp('127.0.0.1', 0))
local addr = assert(server:getsockname())
local received_hello = false

eco.run(function()
    local peer<close> = assert(server:accept())

    local data, err = peer:read(4096, 2.0)
    assert(data and #data > 0, err)
    received_hello = true

    -- Keep TCP open without replying to the TLS ClientHello.
    data, err = peer:read(4096, 20.0)
    assert(data == nil and err == 'closed', err)
end)

local started = time.now()
local client, err = ssl.connect('127.0.0.1', addr.port, { insecure = true })
local elapsed = time.now() - started

assert(received_hello, 'server did not receive ClientHello')
assert(client == nil and err == 'timeout', tostring(err))
assert(elapsed >= 14.0 and elapsed < 18.0,
       string.format('unexpected handshake timeout: %.3fs', elapsed))

print('ssl handshake timeout test passed')
