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

local ok, err = sock:request_dump(msg, function(reply)
    print('Recv from kernel:', reply:payload())
    return true
end)
if not ok then
    print('request fail:', err)
end
