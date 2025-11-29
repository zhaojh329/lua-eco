#!/usr/bin/env lua5.4

local file = require 'eco.file'
local time = require 'eco.time'
local eco = require 'eco'

eco.run(function()
    local f<close>, err = file.open('/tmp/lock-test',
            file.O_RDWR | file.O_CREAT, file.S_IRUSR | file.S_IWUSR)
    assert(f, err)

    local ok, err = f:flock(file.LOCK_EX)
    assert(ok, err)

    print('locked')

    time.sleep(5)

    f:flock(file.LOCK_UN)

    print('unlocked')

    eco.unloop()
end)

eco.loop()
