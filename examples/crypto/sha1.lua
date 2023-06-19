#!/usr/bin/env eco

local sha1 = require 'eco.crypto.sha1'
local hex = require 'eco.hex'

local ctx = sha1.new()
ctx:update('1234')

local hash = ctx:final()
print(hex.encode(hash))

hash = sha1.sum('1234')
print(hex.encode(hash))
