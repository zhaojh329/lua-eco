#!/usr/bin/env eco

local socket = require 'eco.socket'
local rtnl = require 'eco.rtnl'
local sys = require 'eco.sys'
local nl = require 'eco.nl'

local sock, err = nl.open(nl.NETLINK_ROUTE)
if not sock then
    print('open fail:', err)
    return
end

local msg = nl.nlmsg(rtnl.RTM_DELLINK, nl.NLM_F_REQUEST | nl.NLM_F_ACK)

msg:put(rtnl.rtgenmsg({ family = socket.AF_UNSPEC }))
msg:put_attr_str(rtnl.IFLA_IFNAME, 'eth0')

local ok, err = sock:send(msg)
if not ok then
    print('send fail:', err)
    return
end

msg, err = sock:recv()
if not msg then
    print('recv fail:', err)
end

local nlh = msg:next()
if not nlh then
    return
end

if nlh.type == nl.NLMSG_ERROR then
    err = msg:parse_error()
    if err == 0 then
        return
    end

    print('err:', sys.strerror(-err))
end
