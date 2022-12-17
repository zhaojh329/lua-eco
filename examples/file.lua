#!/usr/bin/env eco

local file = require 'eco.file'

for name, info in file.dir('.') do
    print(name, 'type: ' .. info['type'], 'uid: ' .. info.uid, 'size: ' .. info.size)
end


if file.access('/etc/shadow') then
    print('"/etc/shadow" exists')
end

if file.access('/etc/shadow', 'r') then
    print('"/etc/shadow" is readable')
else
    print('"/etc/shadow" is not readable')
end

file.write(1, 'I am eco\n')
file.write(1, 'Please input: ')

local data = file.read(0, 100)
file.write(1, 'You inputed: ' .. data)
