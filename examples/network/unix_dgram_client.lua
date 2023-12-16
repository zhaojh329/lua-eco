#!/usr/bin/env eco

local socket = require 'eco.socket'
local bufio = require 'eco.bufio'
local file = require 'eco.file'
local sys = require 'eco.sys'

sys.signal(sys.SIGINT, function()
    print('\nGot SIGINT, now quit')
    eco.unloop()
end)

local s, err = socket.unix_dgram()
if not s then
    error(err)
end

s:bind('')

local ok, err = s:connect('/tmp/eco.sock')
if not ok then
    error(err)
end

local b = bufio.new(0)

while true do
    file.write(0, 'Please input: ')

    local data = b:read('l')

    if data ~= '' then
        s:send(data)
        local data = s:recv(100)
        print('recv:', data)
    end
end
