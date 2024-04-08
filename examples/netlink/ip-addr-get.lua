#!/usr/bin/env eco

local addr = require 'eco.ip'.address
local socket = require 'eco.socket'

local ifname = 'eth0'

local res, err = addr.get(ifname)
if not res then
    print('get fail:', err)
    return
end

for _, info in pairs(res) do
    if info.family == socket.AF_INET then
        print(info.ifname, 'inet', info.scope)
        print('', info.address, info.broadcast)
    else
        print(info.ifname, 'inet6', info.scope)
        print('', info.address)
    end
    print()
end
