#!/usr/bin/env lua5.4

local shared = require 'eco.shared'
local time = require 'eco.time'
local sys = require 'eco.sys'
local eco = require 'eco'

sys.spawn(function()
    eco.run(function()
        time.sleep(0.2)
        local dict = shared.get('dict')
        dict:set('a', '1')
        dict:set('b', '2')
    end)

    eco.loop()
end)

sys.spawn(function()
    eco.run(function()
        time.sleep(0.5)
        local dict = shared.get('dict')
        print('a:', dict:get('a'))
        print('b:', dict:get('b'))
        dict:del('a')
        print('a:', dict:get('a'))
    end)

    eco.loop()
end)

local dict, err = shared.new('dict')
if not dict then
    error(err)
end

eco.loop()
