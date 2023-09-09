#!/usr/bin/env eco

local file = require 'eco.file'
local time = require 'eco.time'

local fd, err = file.open('/tmp/lock-test', file.O_RDWR)
if not fd then
    print('open fail:', err)
    return
end

local ok, err = file.flock(fd, file.LOCK_EX)
if not ok then
    print('lock fail:', err)
    file.close(fd)
    return
end

print('locked')

time.sleep(5)

file.flock(fd, file.LOCK_UN)

print('unlocked')

file.close(fd)
