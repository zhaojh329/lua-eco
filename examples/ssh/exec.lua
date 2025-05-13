#!/usr/bin/env eco

local ssh = require 'eco.ssh'

local ipaddr = '127.0.0.1'
local port = 22
local username = 'root'
local password = '1'

local session<close>, err = ssh.new(ipaddr, port, username, password)
if not session then
    print('new session fail:', err)
    return
end

local data, exit_code, exit_signal = session:exec('uptime')
if not data then
    print('exec fail:', exit_code)
    return
end

if exit_signal then
    print('Got signal:', exit_signal)
else
    print('Exit:', exit_code)
    print('Output:', data)
end
