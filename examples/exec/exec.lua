#!/usr/bin/env eco

local sys = require 'eco.sys'

local p, err = sys.exec('date', '-u')
if not p then
    print('exec fail:', err)
    return
end

print('pid:', p:pid())

local pid, status = p:wait(10.0)
if not pid then
    print('wait timeout')
    return
end

print('waited pid:', pid)

if status.exited then
    print('terminated normally, exit status:', status.status)
    print('stdout: ', p:read_stdout('*a'))
    print('stderr: ', p:read_stderr('*a'))
elseif status.signaled then
    print('terminated by a signal:', status.status)
end
