#!/usr/bin/env eco

local addr = require 'eco.ip'.address

local ifname = 'eth0'

local ok, err = addr.del(ifname, { address = '192.168.1.2', prefix = 32 })
if not ok then
    print('del fail:', err)
    return
end
