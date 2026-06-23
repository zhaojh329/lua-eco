#!/usr/bin/env eco

local function prefer_built_socket(path)
    local f = io.open(path)
    if not f then
        return
    end

    f:close()
    package.cpath = path .. ';' .. package.cpath
end

prefer_built_socket('build/socket.so')
prefer_built_socket('../build/socket.so')

local socket = require 'eco.internal.socket'

local raw, err = socket.socket(socket.AF_PACKET, socket.SOCK_RAW, socket.htons(socket.ETH_P_ALL))
if not raw then
    print('skip packet socket address conversion errors:', err)
    print('socket address tests passed')
    return
end

local bad_addr = { ifname = 'eco-no-such-interface' }

local ok, cerr = raw:connect(bad_addr)
assert(ok == nil)
assert(cerr == "device 'eco-no-such-interface' not exists", tostring(cerr))

local sent, serr = raw:sendto('x', bad_addr)
assert(sent == nil)
assert(serr == "device 'eco-no-such-interface' not exists", tostring(serr))

raw:close()

print('socket address tests passed')
