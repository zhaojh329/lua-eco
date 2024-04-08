#!/usr/bin/env eco

local addr = require 'eco.ip'.address

local ifname = 'eth0'

local ok, err = addr.add(ifname, { address = '192.168.1.2', prefix = 32, scope = 'global' })
if not ok then
    print('add fail:', err)
    return
end
