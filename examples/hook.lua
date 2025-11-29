#!/usr/bin/env lua5.4

local time = require 'eco.time'
local log = require 'eco.log'
local eco = require 'eco'

local function hook(event)
    local info3 = debug.getinfo(3, 'Sl')

    if not info3 then
        return
    end

    local info2 = debug.getinfo(2, 'nf')

    local src = info3.short_src

    if info3.currentline ~= -1 then
        src = src .. ':' .. info3.currentline
    end

    log.info(event:upper(), info2.name or info2.func, src)
end

eco.run(function()
    while true do
        time.sleep(1)
    end
end)

for _, co in ipairs(eco.all()) do
    debug.sethook(co, hook, 'rc')
end

eco.loop()
