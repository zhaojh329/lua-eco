#!/usr/bin/env eco

local addr = require 'eco.ip'.address

local ifname = 'eth0'

local ok, err = addr.add(ifname, { address = '192.168.1.2', prefix = 32, scope = 'global' })
if not ok then
    print('add fail:', err)
    return
end

local res, err = addr.get(ifname)
if not ok then
    print('get fail:', err)
    return
end

for k, v in pairs(res) do
    print(k .. ':', v)
end

ok, err = addr.del(ifname, { address = '192.168.1.2', prefix = 32 })
if not ok then
    print('del fail:', err)
    return
end
