#!/usr/bin/env eco

local termios = require 'eco.termios'
local file = require 'eco.file'
local eco = require 'eco'

local f<close>, err = file.open('/dev/tty')
assert(f, err)

local attr, err = termios.tcgetattr(f.fd)
assert(attr, err)

local nattr = attr:clone()

nattr:clr_flag('l', termios.ECHO)
nattr:set_speed(termios.B115200)

local ok, err = termios.tcsetattr(f.fd, termios.TCSANOW, nattr)
assert(ok, err)

eco.run(function()
    local data, err = f:read(1024)
    assert(data, err)

    print('read:', data)

    -- recover term attr
    termios.tcsetattr(f.fd, termios.TCSANOW, attr)

    eco.unloop()
end)

eco.loop()
