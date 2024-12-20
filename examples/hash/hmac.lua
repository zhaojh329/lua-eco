#!/usr/bin/env eco

local sha256 = require 'eco.hash.sha256'
local hmac = require 'eco.hash.hmac'
local hex = require 'eco.encoding.hex'

-- also, you can use other hash modules, such as sha1, md5.
local ctx = hmac.new(sha256, 'key')

ctx:update('12')
ctx:update('34')

local hash = ctx:final()
print(hex.encode(hash))

hash = hmac.sum(sha256, 'key', '1234')
print(hex.encode(hash))
