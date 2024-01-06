#!/usr/bin/env eco

local time = require 'eco.time'
local sys = require 'eco.sys'
local log = require 'eco.log'

local pid = sys.spawn(function()
    log.info('sub process:')

    while true do
        log.info('sub:', time.now())
        time.sleep(1)
    end
end)

log.info('spawn a process:', pid)

while true do
    log.info('parent:', time.now())
    time.sleep(1)
end
