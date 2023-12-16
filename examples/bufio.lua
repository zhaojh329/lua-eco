#!/usr/bin/env eco

local bufio = require 'eco.bufio'

local b = bufio.new(0)

print('read:', b:read(1))
print('peek:', b:peek(1))
print('read:', b:read(1))
print('discard:', b:discard(4))
print('readline:', b:read('l'))
print('readline:', b:read('L'))
