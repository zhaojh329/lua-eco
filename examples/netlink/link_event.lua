#!/usr/bin/env eco

local hex = require 'eco.encoding.hex'
local rtnl = require 'eco.rtnl'
local sys = require 'eco.sys'
local bit = require 'eco.bit'
local nl = require 'eco.nl'

local sock, err = nl.open(nl.NETLINK_ROUTE)
if not sock then
    print('open fail:', err)
    return
end

local ok, err = sock:bind(rtnl.RTNLGRP_LINK)
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

        if nlh.type == rtnl.RTM_NEWLINK or nlh.type == rtnl.RTM_DELLINK then
            if nlh.type == rtnl.RTM_NEWLINK then
                print('new link')
            elseif nlh.type == rtnl.RTM_DELLINK then
                print('del link')
            end

            local info = rtnl.parse_ifinfomsg(msg)
            for k, v in pairs(info) do
                if k == 'flags' or k == 'change' then
                    print(k .. ':', string.format('0x%x', v))
                else
                    print(k .. ':', v)
                end
            end

            if bit.band(info.flags, rtnl.IFF_RUNNING) > 0 then
                print('RUNNING')
            else
                print('NOT RUNNING')
            end

            local attrs = msg:parse_attr(rtnl.IFINFOMSG_SIZE)

            if attrs[rtnl.IFLA_IFNAME] then
                local ifname = nl.attr_get_str(attrs[rtnl.IFLA_IFNAME])
                print('ifname:', ifname)
            end

            if attrs[rtnl.IFLA_MTU] then
                local mtu = nl.attr_get_u32(attrs[rtnl.IFLA_MTU])
                print('mtu:', mtu)
            end

            if attrs[rtnl.IFLA_ADDRESS] then
                local addr = nl.attr_get_payload(attrs[rtnl.IFLA_ADDRESS])
                print('addr:', hex.encode(addr, ':'))
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
