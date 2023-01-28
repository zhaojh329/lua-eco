#!/usr/bin/env eco

local termios = require 'eco.termios'
local file = require 'eco.file'
local sys = require 'eco.sys'

local done = false

sys.signal(sys.SIGINT, function()
    done = true
    eco.unloop()
end)

local fd = file.open('/dev/tty')

local attr, err = termios.tcgetattr(fd)
if not attr then
    print('tcgetattr:', err)
    return
end

local nattr = attr:clone()

nattr:clr_flag('l', termios.ECHO)
nattr:set_speed(termios.B115200)

local ok, err = termios.tcsetattr(fd, termios.TCSANOW, nattr)
if not ok then
    print('tcsetattr:', err)
    return
end

while not done do
    local data, err = file.read(fd, 1024)
    if not data then
        print('read file:', err)
        break
    end

    print('read:', data)
end

-- recover term attr
termios.tcsetattr(fd, termios.TCSANOW, attr)

file.close(fd)
