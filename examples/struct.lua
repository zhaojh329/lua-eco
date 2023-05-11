#!/usr/bin/env eco

local hex = require 'eco.encoding.hex'
local struct = require 'eco.struct'

print(hex.dump(struct.pack('cc', 'a', 'x')))

print(hex.dump(struct.pack('cci', 'a', 'x', 12)))

print(hex.dump(struct.pack('u8u32', 1, 2)))

print(hex.dump(struct.pack('i8i32', 1, 2)))

print(hex.dump(struct.pack('u32S', 1, 'hello')))
