#!/usr/bin/env eco

local socket = require 'eco.socket'
local bufio = require 'eco.bufio'
local time = require 'eco.time'

eco.run(function()
    local s, err = socket.listen_tcp(nil, 8080, { reuseaddr = true })
    if not s then
        error(err)
    end

    local c, peer = s:accept()
    if not c then
        error(peer)
    end

    print('send: 12')
    c:send('12')
    time.sleep(0.1)

    print('send: 345')
    c:send('345')
    time.sleep(0.1)

    print('send: 678\\nqwer')
    c:send('678\nqwer')
    time.sleep(0.1)

    print('send: eco')
    c:send('eco')
end)

time.sleep(1)

local s, err = socket.connect_tcp('127.0.0.1', 8080)
if not s then
    error(err)
end

local b = bufio.new({ w = eco.watcher(eco.IO, s:getfd()) })

print('read:', b:read(100))
print('peek:', b:peek(10))
print('discard:', b:discard(4))
print('readline:', b:readline())
print('read:', b:read(100))
print('read:', b:read(100))
