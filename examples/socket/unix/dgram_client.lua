#!/usr/bin/env eco

local socket = require 'eco.socket'
local eco = require 'eco'

local s, err = socket.unix_dgram()
if not s then
    error(err)
end

s:bind('')

local ok, err = s:connect('/tmp/eco.sock')
if not ok then
    error(err)
end

local stdin = eco.reader(0)

while true do
    print('Please input:')

    local data = stdin:read('l')

    if data ~= '' then
        s:send(data)
        data = s:recv(100)
        print('recv:', data)
    end
end
