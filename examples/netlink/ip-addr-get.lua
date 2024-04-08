#!/usr/bin/env eco

local addr = require 'eco.ip'.address

local ifname = 'eth0'

local res, err = addr.get(ifname)
if not res then
    print('get fail:', err)
    return
end

for k, v in pairs(res) do
    print(k .. ':', v)
end
