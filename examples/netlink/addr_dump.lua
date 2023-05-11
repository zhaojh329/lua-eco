#!/usr/bin/env eco

local network = require 'eco.network'
local socket = require 'eco.socket'
local rtnl = require 'eco.rtnl'
local bit = require 'eco.bit'
local sys = require 'eco.sys'
local nl = require 'eco.nl'

local sock, err = nl.open(nl.NETLINK_ROUTE)
if not sock then
    print('open fail:', err)
    return
end

local msg = nl.nlmsg(rtnl.RTM_GETADDR, bit.bor(nl.NLM_F_REQUEST, nl.NLM_F_DUMP))

msg:put(rtnl.ifaddrmsg({ family = socket.AF_UNSPEC }))

local ok, err = sock:send(msg)
if not ok then
    print('send fail:', err)
    return
end

while true do
    msg, err = sock:recv()
    if not msg then
        print('recv fail:', err)
        return
    end

    while true do
        local nlh = msg:next()
        if not nlh then
            break
        end

        if nlh.type == rtnl.RTM_NEWADDR then
            local info = rtnl.parse_ifaddrmsg(msg)
            for k, v in pairs(info) do
                if k == 'flags' then
                    print(k .. ':', string.format('0x%x', v))
                else
                    print(k .. ':', v)
                end

                if k == 'index' then
                    print('ifname:', network.if_indextoname(v))
                end
            end

            local attrs = msg:parse_attr(rtnl.IFADDRMSG_SIZE)

            if attrs[rtnl.IFA_ADDRESS] then
                print('addr:', socket.inet_ntop(info.family, nl.attr_get_payload(attrs[rtnl.IFA_ADDRESS])))
            end

            if attrs[rtnl.IFA_BROADCAST] then
                print('broadcast:', socket.inet_ntop(info.family, nl.attr_get_payload(attrs[rtnl.IFA_BROADCAST])))
            end

            if attrs[rtnl.IFA_LABEL] then
                print('label:', nl.attr_get_str(attrs[rtnl.IFA_LABEL]))
            end

            print()
        elseif nlh.type == nl.NLMSG_ERROR then
            err = msg:parse_error()
            if err < 0 then
                print('err:', sys.strerror(-err))
            end
            return
        elseif nlh.type == nl.NLMSG_DONE then
            return
        end
    end
end
