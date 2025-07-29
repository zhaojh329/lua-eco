#!/usr/bin/env eco

local shared = require 'eco.shared'
local time = require 'eco.time'
local sys = require 'eco.sys'

sys.spawn(function()
    time.sleep(0.2)
    local dict = shared.get('dict')
    dict:set('a', '1')
    dict:set('b', '2')
end)

sys.spawn(function()
    time.sleep(0.5)
    local dict = shared.get('dict')
    print('a:', dict:get('a'))
    print('b:', dict:get('b'))
    dict:del('a')
    print('a:', dict:get('a'))
end)

sys.signal(sys.SIGINT, function()
    print('\nGot SIGINT, now quit')
    eco.unloop()
end)

local dict, err = shared.new('dict')
if not dict then
    error(err)
end

time.sleep(1)
