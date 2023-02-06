#!/usr/bin/env eco

local hex = require 'eco.encoding.hex'

local src = '48656c6c6f2c2065636f21'

local dst, err = hex.decode(src)
if not dst then
    print('decode fail:', err)
    return
end

print(dst)

print(hex.encode(dst))
