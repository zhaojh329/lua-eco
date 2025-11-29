#!/usr/bin/env lua5.4

local eco = require 'eco'

eco.set_panic_hook(function(...)
    print('panic_hook:')

    for _, v in ipairs({...}) do
        print(v)
    end
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
