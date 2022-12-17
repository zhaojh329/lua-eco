#!/usr/bin/env eco

local sys = require 'eco.sys'

local p, err = sys.exec('date', '-u')
if not p then
    print('exec fail:', err)
    return
end

local pid, status = p:wait(10.0)
if not pid then
    print('wait timeout')
    return
end

print('pid:', pid)

if status.exited then
    print('terminated normally, exit status:', status.status)
    print('stdout: ', p:read_stdout(1024))
    print('stderr: ', p:read_stderr(1024))
elseif status.signaled then
    print('terminated by a signal:', status.status)
end
