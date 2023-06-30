#!/usr/bin/env eco

local file = require 'eco.file'
local time = require 'eco.time'
local sys = require 'eco.sys'

local fd, err = file.open('/tmp/lock-test', file.O_RDWR)
if not fd then
    print('open fail:', err)
    return
end

while true do
    local ok, errno, err = file.flock(fd, file. LOCK_EX)
    if ok then
        print('lock ok')
        break
    end

    if errno ~= sys.EAGAIN then
        print('lock fail:', err)
        file.close(fd)
        return
    end
    time.sleep(0.1)
end

time.sleep(5)

file.flock(fd, file. LOCK_UN)

print('unlocked')

time.sleep(5)

file.close(fd)
