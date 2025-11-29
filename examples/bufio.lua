#!/usr/bin/env lua5.4

local bufio = require 'eco.bufio'
local eco = require 'eco'

eco.run(function()
    local b = bufio.new(0)

    print('read:', b:read(1))
    print('peek:', b:peek(1))
    print('read:', b:read(1))
    print('discard:', b:discard(4))
    print('readline:', b:read('l'))
    print('readline:', b:read('L'))
end)

eco.loop()
