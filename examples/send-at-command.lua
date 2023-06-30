#!/usr/bin/env eco

local termios = require 'eco.termios'
local bufio = require 'eco.bufio'
local file = require 'eco.file'

local function send_at(cmd, fd, b)
    termios.tcflush(fd, termios.TCIOFLUSH)

    file.write(fd, cmd .. '\n')

    local data = {}

    while true do
        local line, err = b:readline()
        if not line then
            return nil, err
        end

        if line ~= '' then
            if line == 'OK' then
                return table.concat(data, '\n')
            end

            if line == 'ERROR' then
                return nil, 'ERROR'
            end

            data[#data + 1] = line
        end
    end
end

local fd, err = file.open('/dev/ttyUSB2', file.O_RDWR)
if not fd then
    print('open fail:', err)
    return
end

local attr, err = termios.tcgetattr(fd)
if not attr then
    print('tcgetattr:', err)
    return
end

local nattr = attr:clone()

nattr:clr_flag('l', termios.ECHO)
nattr:clr_flag('l', termios.ICANON)

nattr:clr_flag('i', termios.ICRNL)

nattr:set_cc(termios.VMIN, 1)
nattr:set_cc(termios.VTIME, 0)

nattr:set_speed(termios.B115200)

local ok, err = termios.tcsetattr(fd, termios.TCSANOW, nattr)
if not ok then
    print('tcsetattr:', err)
    return
end

local b = bufio.new({ fd = fd, w = eco.watcher(eco.IO, fd) })

local res, err = send_at('ATI', fd, b)
if not res then
    print('send fail:', err)
else
    print(res)
end

-- recover term attr
termios.tcsetattr(fd, termios.TCSANOW, attr)

file.close(fd)
