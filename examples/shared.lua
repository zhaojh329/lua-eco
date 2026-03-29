#!/usr/bin/env eco

local shared = require 'eco.shared'
local time = require 'eco.time'
local sys = require 'eco.sys'

local name = string.format('dict-%d', sys.getpid())

local dict, err = shared.new(name, 1024)

if not dict then
    error(err)
end

sys.spawn(function()
    time.sleep(0.2)

    local d = assert(shared.get(name))
    assert(d:set('n', 1))
    assert(d:set('a', 'hello'))
    assert(d:set('b', true))
    assert(d:set('c', 1, 0.01))
    assert(d:set('d', 2))
end)

time.sleep(0.5)

local d = assert(shared.get(name))

local keys = d:get_keys()

for _, k in ipairs(keys) do
    local v = d:get(k)
    if type(v) == 'number' then
        print(k, math.type(v), v)
    else
        print(k, type(v), v)
    end
end

print('del a', d:del('a'))
print('get a', d:get('a'))

d:incr('d', 10)
print('get d', d:get('d'))
