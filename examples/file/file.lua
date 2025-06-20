#!/usr/bin/env eco

local file = require 'eco.file'

if file.access('/etc/shadow') then
    print('"/etc/shadow" exists')
end

if file.access('/etc/shadow', 'r') then
    print('"/etc/shadow" is readable')
else
    print('"/etc/shadow" is not readable')
end

print(file.readfile('/etc/os-release'))

file.writefile('/tmp/eco-test', 'I am eco\n')
