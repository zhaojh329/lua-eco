#!/usr/bin/env eco

local socket = require 'eco.socket'
local time = require 'eco.time'
local sys = require 'eco.sys'

local sock1, sock2 = socket.socketpair(socket.AF_UNIX, socket.SOCK_STREAM)
if not sock1 then
    error(sock2)
end

sys.spawn(function()
    sock2:close()

    print('child pid', sys.getpid())

    local data = sock1:read('l')
    print('child recv:', data)
end)

sock1:close()

print('parent pid', sys.getpid())

sock2:send('I am parent\n')

time.sleep(1)
