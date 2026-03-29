#!/usr/bin/env eco

local eco = require 'eco'

eco.set_panic_hook(function(traceback1, traceback2)
    print('panic_hook:')

    print(traceback1)
    print(traceback2)
end)

local function test2()
    -- call a nil value
    x()
end

local function test1()
    test2()
end

local function main()
    eco.run(function ()
        test1()
    end)
end

main()
