#!/usr/bin/env eco

local link = require 'eco.ip'.link

local ifname = 'eth0'

local ok, err = link.set(ifname, { address = '00:82:a2:c0:31:99' })
if not ok then
    print('set fail:', err)
    return
end

local res, err = link.get(ifname)
if not res then
    print('get fail:', err)
    return
end

for k, v in pairs(res) do
    print(k .. ':', v)
end
