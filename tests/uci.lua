#!/usr/bin/env eco

local file = require 'eco.file'
local uci = require 'eco.uci'

local confdir = '/tmp/eco-uci-confdir'
local savedir = '/tmp/eco-uci-savedir'

file.mkdir(confdir)
file.mkdir(savedir)

file.writefile(confdir .. '/network', '')

local c = uci.cursor(confdir, savedir)

print('confdir:', c:get_confdir())
print('savedir:', c:get_savedir())

c:set('network', 'lan', 'interface')
c:set('network', 'lan', 'ipaddr', '192.168.1.1')

local sid = c:add('network', 'switch')
c:set('network', sid, 'name', 'switch0')

c:commit('network')

c = uci.cursor(confdir, savedir)

print('list configs:')
for _, config in ipairs(c:list_configs()) do
    print(file.readfile(confdir .. '/' .. config))
end

print('foreach:')
c:foreach('network', nil, function(s)
    print('', s['.type'], s['.name'])
end)

print('each:')
for s in c:each('network') do
    print('', s['.type'], s['.name'])
end

c:rename('network', '@switch[0]', 'switch0')
c:set('network', 'switch0', 'vid', 10)

print('after rename, each:')
for s in c:each('network') do
    print('', s['.type'], s['.name'])
end

assert(c:get('network', 'switch0', 'vid') == '10')

os.remove(confdir .. '/network')
os.remove(savedir .. '/network')

os.remove(confdir)
os.remove(savedir)
