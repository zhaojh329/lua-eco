#!/usr/bin/env lua5.4

local sys = require 'eco.sys'
local eco = require 'eco'

eco.run(function()
    local p, err = sys.exec({ 'env' }, { 'a=1', 'b=2' })
    if not p then
        print('exec fail:', err)
        return
    end

    print(p:read_stdout('*a'))

    eco.unloop()
end)

eco.loop()
