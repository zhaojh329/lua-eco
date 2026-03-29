#!/usr/bin/env eco

local time = require 'eco.time'
local sys = require 'eco.sys'

local sig = sys.signal(sys.SIGINT, function()
    print('\nGot SIGINT, now quit')
end)

time.at(3, function()
    sig:close()
    print('Signal monitoring has been cancelled')
end)
