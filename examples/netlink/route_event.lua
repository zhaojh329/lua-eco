#!/usr/bin/env eco

local hex = require 'eco.encoding.hex'
local socket = require 'eco.socket'
local rtnl = require 'eco.rtnl'
local sys = require 'eco.sys'
local nl = require 'eco.nl'

local sock, err = nl.open(nl.NETLINK_ROUTE)
if not sock then
    print('open fail:', err)
    return
end

local ok, err = sock:bind(rtnl.RTMGRP_IPV4_ROUTE | rtnl.RTMGRP_IPV6_ROUTE)
if not ok then
    print('bind fail:', err)
    return
end

while true do
    local msg, err = sock:recv()
    if not msg then
        print('recv fail:', err)
        return
    end

    while true do
        local nlh = msg:next()
        if not nlh then
            break
        end

        if nlh.type == rtnl.RTM_NEWROUTE or nlh.type == rtnl.RTM_DELROUTE then
            if nlh.type == rtnl.RTM_NEWROUTE then
                print('new route')
            elseif nlh.type == rtnl.RTM_DELROUTE then
                print('del route')
            end

            local rt = rtnl.parse_rtmsg(msg)
            for k, v in pairs(rt) do
                if k == 'flags' then
                    print(k .. ':', string.format('0x%x', v))
                else
                    print(k .. ':', v)
                end
            end

            local attrs = msg:parse_attr(rtnl.RTMSG_SIZE)

            if attrs[rtnl.RTA_DST] then
                local dst = nl.attr_get_payload(attrs[rtnl.RTA_DST])
                print('dst:', socket.inet_ntop(socket.AF_INET, dst))
            end

            if attrs[rtnl.RTA_SRC] then
                local src = nl.attr_get_payload(attrs[rtnl.RTA_SRC])
                print('src:', socket.inet_ntop(socket.AF_INET, src))
            end

            if attrs[rtnl.RTA_OIF] then
                local oif = nl.attr_get_u32(attrs[rtnl.RTA_OIF])
                print('oif:', socket.if_indextoname(oif))
            end

            if attrs[rtnl.RTA_GATEWAY] then
                local gw = nl.attr_get_payload(attrs[rtnl.RTA_GATEWAY])
                print('gateway:', socket.inet_ntop(socket.AF_INET, gw))
            end

            print()
        elseif nlh.type == nl.NLMSG_ERROR then
            err = msg:parse_error()
            if err < 0 then
                print('err:', sys.strerror(-err))
            end
            return
        end
    end
end
