#!/usr/bin/env eco

local socket = require 'eco.socket'
local rtnl = require 'eco.rtnl'
local nl = require 'eco.nl'

local sock, err = nl.open(nl.NETLINK_ROUTE)
if not sock then
    print('open fail:', err)
    return
end

local msg = nl.nlmsg(rtnl.RTM_DELLINK, nl.NLM_F_REQUEST | nl.NLM_F_ACK)

msg:put(rtnl.rtgenmsg({ family = socket.AF_UNSPEC }))
msg:put_attr_str(rtnl.IFLA_IFNAME, 'eth0')

local ok, err = sock:request_ack(msg)
if not ok then
    print('err:', err)
end
