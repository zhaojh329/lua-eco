#!/usr/bin/env eco

local sha256 = require 'eco.hash.sha256'
local hex = require 'eco.encoding.hex'

local ctx = sha256.new()

ctx:update('12')
ctx:update('34')

local hash = ctx:final()
print(hex.encode(hash))


hash = sha256.sum('1234')
print(hex.encode(hash))
