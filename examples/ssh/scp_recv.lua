#!/usr/bin/env lua5.4

local ssh = require 'eco.ssh'
local eco = require 'eco'

local ipaddr = '127.0.0.1'
local port = 22
local username = 'root'
local password = '1'

eco.run(function()
    local session<close>, err = ssh.new(ipaddr, port, username, password)
    if not session then
        print('new session fail:', err)
        return
    end

    -- receive as a string returned
    local data, err = session:scp_recv('/etc/os-release')
    if not data then
        print('recv fail:', err)
        return
    end

    print(data)

    -- receive to a local file
    local n, err = session:scp_recv('/etc/os-release', '/tmp/os-release')
    if not n then
        print('recv fail:', err)
        return
    end

    print('Got', n, 'bytes, stored into "/tmp/os-release"')
end)

eco.loop()
