#!/usr/bin/env eco

local binary = require 'eco.binary'

-- hex: 1234
local data = '\18\52'

print(string.format('0x%x', binary.read_u16(data)))

print(string.format('0x%x', binary.read_u16le(data)))

print(string.format('0x%x', binary.read_u16be(data)))

-- verify the returned value is valid
local offset = 100
local val, ok = binary.read_u16(data, offset)
if not ok then
    print('read fail')
else
    print('read value:', val)
end
