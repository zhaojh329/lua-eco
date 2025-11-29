#!/usr/bin/env lua5.4

local time = require 'eco.time'
local sys = require 'eco.sys'
local log = require 'eco.log'
local eco = require 'eco'

local pid = sys.spawn(function()
    log.info('sub process:')

    eco.run(function()
        while true do
            log.info('sub:', time.now())
            time.sleep(1)
        end
    end)

    eco.loop()
end)

log.info('spawn a process:', pid)

eco.run(function()
    while true do
        log.info('parent:', time.now())
        time.sleep(1)
    end
end)

eco.loop()
