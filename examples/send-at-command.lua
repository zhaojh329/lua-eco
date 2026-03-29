#!/usr/bin/env eco

local termios = require 'eco.termios'
local file = require 'eco.file'

local function send_at(cmd, f)
    termios.tcflush(f.fd, termios.TCIOFLUSH)

    f:write(cmd .. '\n')

    local data = {}

    while true do
        local line, err = f:read('l')
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

local f, err = file.open('/dev/ttyUSB2', file.O_RDWR)
assert(f, err)

local attr, err = termios.tcgetattr(f.fd)
assert(attr, err)

local nattr = attr:clone()

nattr:clr_flag('l', termios.ECHO)
nattr:clr_flag('l', termios.ICANON)

nattr:clr_flag('i', termios.ICRNL)

nattr:set_cc(termios.VMIN, 1)
nattr:set_cc(termios.VTIME, 0)

nattr:set_speed(termios.B115200)

local ok, err = termios.tcsetattr(f.fd, termios.TCSANOW, nattr)
assert(ok, err)

local res, err = send_at('ATI', f)
if not res then
    print('send fail:', err)
else
    print(res)
end

-- recover term attr
termios.tcsetattr(f.fd, termios.TCSANOW, attr)
