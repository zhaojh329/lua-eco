#!/usr/bin/env eco

local socket = require 'eco.socket'
local bufio = require 'eco.bufio'
local file = require 'eco.file'
local sys = require 'eco.sys'

sys.signal(sys.SIGINT, function()
    print('\nGot SIGINT, now quit')
    eco.unloop()
end)

local multicast_addr = '224.0.0.2'
local multicast_port = 8080

local sock, err = socket.udp()
if not sock then
    error(err)
end

local b = bufio.new(0)

while true do
    file.write(0, 'Please input: ')

    local data = b:read('l')

    if data ~= '' then
        sock:sendto(data, multicast_addr, multicast_port)
    end
end
