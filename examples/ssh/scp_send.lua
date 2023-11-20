#!/usr/bin/env eco

local ssh = require 'eco.ssh'

local ipaddr = '127.0.0.1'
local port = 22
local username = 'root'
local password = '1'

local session, err = ssh.new(ipaddr, port, username, password)
if not session then
    print('new session fail:', err)
    return
end

-- send a string
local ok, err = session:scp_send('12345\n', '/tmp/test1')
if not ok then
    print('send fail:', err)
    return
end

-- send a file
local ok, err = session:scp_sendfile('test', '/tmp/test2')
if not ok then
    print('send fail:', err)
    return
end

session:free()
