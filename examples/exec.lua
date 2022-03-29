#!/usr/bin/env lua

local eco = require "eco"
local sys = require "eco.sys"

eco.run(
    function()
        local p = sys.exec("date", "-u")
        local date = p:stdout_read()
        print("date:", date)

        local code = p:wait()
        print("code:", code)
    end
)

eco.loop()
