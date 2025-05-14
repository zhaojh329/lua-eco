#!/usr/bin/env eco

local socket = require 'eco.socket'
local sys = require 'eco.sys'

sys.signal(sys.SIGINT, function()
    print('\nGot SIGINT, now quit')
    eco.unloop()
end)

local s, err = socket.unix_dgram()
if not s then
    error(err)
end

local ok, err = s:bind('/tmp/eco.sock')
if not ok then
    error(err)
end

while true do
    local data, peer = s:recvfrom(1024)
    if not data then
        print(peer)
        break
    end

    print('recv:', data)

    if peer then
        s:sendto('I am eco:' .. data, peer.path)
    end
end
