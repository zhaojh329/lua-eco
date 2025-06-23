#!/usr/bin/env eco

local sys = require 'eco.sys'

local p, err = sys.exec({ 'env' }, { 'a=1', 'b=2' })
if not p then
    print('exec fail:', err)
    return
end

print(p:read_stdout('*a'))
