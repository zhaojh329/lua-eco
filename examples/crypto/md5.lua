#!/usr/bin/env eco

local md5 = require 'eco.crypto.md5'
local hex = require 'eco.encoding.hex'

local ctx = md5.new()

ctx:update('12')
ctx:update('34')

local hash = ctx:final()
print(hex.encode(hash))


hash = md5.sum('1234')
print(hex.encode(hash))
