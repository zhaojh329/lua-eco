#!/usr/bin/env lua5.4

local socket = require 'eco.socket'
local bufio = require 'eco.bufio'
local sys = require 'eco.sys'
local eco = require 'eco'

sys.signal(sys.SIGINT, function()
    print('\nGot SIGINT, now quit')
    eco.unloop()
end)

local function handle_connection(c)
    local b = bufio.new(c)

    while true do
        local data, err = b:read('l')
        if not data then
            print(err)
            break
        end
        print('read:', data)
        c:send('I am eco:' .. data .. '\n')
    end
end

local s, err = socket.listen_tcp(nil, 8080, { reuseaddr = true })
if not s then
    error(err)
end

print('listen...')

eco.run(function()
    while true do
        local c, peer = s:accept()
        if not c then
            print(peer)
            break
        end

        print('new connection:', peer.ipaddr, peer.port)

        eco.run(handle_connection, c)
    end
end)

eco.loop()
