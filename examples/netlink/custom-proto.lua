#!/usr/bin/env eco

local nl = require 'eco.nl'

local NETLINK_TEST = 25

local sock, err = nl.open(NETLINK_TEST)
if not sock then
    print('open fail:', err)
    return
end

local msg = nl.nlmsg(0, 0)

msg:put('Hello, I am lua-eco!')

local ok, err = sock:send(msg)
if not ok then
    print('send fail:', err)
    return
end

msg, err = sock:recv()
if not msg then
    print('recv fail:', err)
end

if msg:next() then
    print('Recv from kernel:', msg:payload())
end
