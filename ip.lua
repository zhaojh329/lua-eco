-- SPDX-License-Identifier: MIT
-- Author: Jianhui Zhao <zhaojh329@gmail.com>

local hex = require 'eco.encoding.hex'
local socket = require 'eco.socket'
local rtnl = require 'eco.rtnl'
local sys = require 'eco.sys'
local nl = require 'eco.nl'

local M = {}

local function rtnl_send(msg)
    local sock, err = nl.open(nl.NETLINK_ROUTE)
    if not sock then
        return nil, err
    end

    local ok, err = sock:send(msg)
    if not ok then
        return nil, err
    end

    msg, err = sock:recv()
    if not msg then
        return nil, err
    end

    local nlh = msg:next()
    if not nlh then
        return nil, 'no ack'
    end

    if nlh.type == nl.NLMSG_ERROR then
        err = msg:parse_error()
        if err == 0 then
            return true
        end

        return nil, 'RTNETLINK answers: ' .. sys.strerror(-err)
    end

    return nil, 'no ack'
end

local link = {}

--[[
    syntax:
        local link = require 'eco.ip'.link
        local ok, err = link.set('eth0', { up = true })

    In case of success, it returns true; in case of error, it returns
    nil with a string describing the error.

    Supported attributes:
        up: boolean
        down: boolean
        arp: boolean
        dynamic: boolean
        multicast: boolean
        allmulticast: boolean
        promisc: boolean
        carrier: boolean
        txqueuelen: number
        address: string
        broadcast: string
        mtu: number
        alias: string
        master: string
        nomaster: boolean
--]]
function link.set(dev, attrs)
    local dev_index = socket.if_nametoindex(dev)
    if not dev_index then
        return nil, 'no such device'
    end

    attrs = attrs or {}

    local msg = nl.nlmsg(rtnl.RTM_SETLINK, nl.NLM_F_REQUEST | nl.NLM_F_ACK)

    local change = 0
    local flags = 0

    if attrs.up then
        change = change | rtnl.IFF_UP
        flags = flags | rtnl.IFF_UP
    elseif attrs.down then
        change = change | rtnl.IFF_UP
    end

    if attrs.arp ~= nil then
        change = change | rtnl.IFF_NOARP

        if not attrs.arp then
            flags = flags | rtnl.IFF_NOARP
        end
    end

    if attrs.dynamic ~= nil then
        change = change | rtnl.IFF_DYNAMIC

        if attrs.dynamic then
            flags = flags | rtnl.IFF_DYNAMIC
        end
    end

    if attrs.multicast ~= nil then
        change = change | rtnl.IFF_MULTICAST

        if attrs.multicast then
            flags = flags | rtnl.IFF_MULTICAST
        end
    end

    if attrs.allmulticast ~= nil then
        change = change | rtnl.IFF_MULTICAST

        if attrs.allmulticast then
            flags = flags | rtnl.IFF_ALLMULTI
        end
    end

    if attrs.promisc ~= nil then
        change = change | rtnl.IFF_PROMISC

        if attrs.promisc then
            flags = flags | rtnl.IFF_PROMISC
        end
    end

    msg:put(rtnl.ifinfomsg({
        family = socket.AF_UNSPEC,
        index = dev_index,
        change = change,
        flags = flags
    }))

    if attrs.carrier ~= nil then
        msg:put_attr_u8(rtnl.IFLA_CARRIER, attrs.carrier and 1 or 0)
    end

    if attrs.txqueuelen then
        msg:put_attr_u32(rtnl.IFLA_TXQLEN, attrs.txqueuelen)
    end

    if attrs.address then
        msg:put_attr(rtnl.IFLA_ADDRESS, hex.decode(attrs.address:gsub(':', '')))
    end

    if attrs.broadcast then
        msg:put_attr(rtnl.IFLA_BROADCAST, hex.decode(attrs.broadcast:gsub(':', '')))
    end

    if attrs.mtu then
        msg:put_attr_u32(rtnl.IFLA_MTU, attrs.mtu)
    end

    if attrs.alias then
        msg:put_attr_str(rtnl.IFLA_IFALIAS, attrs.alias)
    end

    if attrs.master then
        local master = attrs.master
        local index = socket.if_nametoindex(master)
        if not index then
            return nil, 'Device does not exist: ' .. master
        end
        msg:put_attr_u32(rtnl.IFLA_MASTER, index)
    end

    if attrs.nomaster then
        msg:put_attr_u32(rtnl.IFLA_MASTER, 0)
    end

    return rtnl_send(msg)
end

function link.get(dev)
    local dev_index = socket.if_nametoindex(dev)
    if not dev_index then
        return nil, 'no such device'
    end

    local sock, err = nl.open(nl.NETLINK_ROUTE)
    if not sock then
        return nil, err
    end

    local msg = nl.nlmsg(rtnl.RTM_GETLINK, nl.NLM_F_REQUEST)

    msg:put(rtnl.ifinfomsg({ family = socket.AF_UNSPEC, index = dev_index }))

    local ok, err = sock:send(msg)
    if not ok then
        return nil, err
    end

    msg, err = sock:recv()
    if not msg then
        return nil, err
    end

    local nlh = msg:next()
    if not nlh then
        return nil, 'no ack'
    end

    if nlh.type == nl.NLMSG_ERROR then
        err = msg:parse_error()
        if err == 0 then
            return true
        end

        return nil, 'RTNETLINK answers: ' .. sys.strerror(-err)
    end

    local res = {
        up = false,
        running = false,
        arp = true,
        dynamic = false,
        multicast = false,
        allmulticast = false,
        promisc = false
    }

    local info = rtnl.parse_ifinfomsg(msg)

    if info.flags & rtnl.IFF_UP > 0 then
        res.up = true
    end

    if info.flags & rtnl.IFF_RUNNING > 0 then
        res.running = true
    end

    if info.flags & rtnl.IFF_NOARP > 0 then
        res.arp = false
    end

    if info.flags & rtnl.IFF_DYNAMIC > 0 then
        res.dynamic = true
    end

    if info.flags & rtnl.IFF_MULTICAST > 0 then
        res.multicast = true
    end

    if info.flags & rtnl.IFF_ALLMULTI > 0 then
        res.allmulticast = true
    end

    if info.flags & rtnl.IFF_PROMISC > 0 then
        res.promisc = true
    end

    local attrs = msg:parse_attr(rtnl.IFINFOMSG_SIZE)

    if attrs[rtnl.IFLA_CARRIER] then
        res.carrier = nl.attr_get_u8(attrs[rtnl.IFLA_CARRIER]) == 1 and true or false
    end

    if attrs[rtnl.IFLA_IFNAME] then
        res.ifname = nl.attr_get_str(attrs[rtnl.IFLA_IFNAME])
    end

    if attrs[rtnl.IFLA_IFALIAS] then
        res.alias = nl.attr_get_str(attrs[rtnl.IFLA_IFALIAS])
    end

    if attrs[rtnl.IFLA_MASTER] then
        local idx = nl.attr_get_u32(attrs[rtnl.IFLA_MASTER])
        res.master = socket.if_indextoname(idx)
    end

    if attrs[rtnl.IFLA_MTU] then
        res.mtu = nl.attr_get_u32(attrs[rtnl.IFLA_MTU])
    end

    if attrs[rtnl.IFLA_TXQLEN] then
        res.txqueuelen = nl.attr_get_u32(attrs[rtnl.IFLA_TXQLEN])
    end

    if attrs[rtnl.IFLA_ADDRESS] then
        local addr = nl.attr_get_payload(attrs[rtnl.IFLA_ADDRESS])
        res.address = hex.encode(addr, ':')
    end

    if attrs[rtnl.IFLA_BROADCAST] then
        local addr = nl.attr_get_payload(attrs[rtnl.IFLA_BROADCAST])
        res.broadcast = hex.encode(addr, ':')
    end

    return res
end

M.link = link

local address = {}

local rtscope_to_num = {
    global = rtnl.RT_SCOPE_UNIVERSE,
    nowhere = rtnl.RT_SCOPE_NOWHERE,
    host = rtnl.RT_SCOPE_HOST,
    link = rtnl.RT_SCOPE_LINK,
    site = rtnl.RT_SCOPE_SITE
}

local rtscope_to_name = {
    [rtnl.RT_SCOPE_UNIVERSE] = 'global',
    [rtnl.RT_SCOPE_NOWHERE] = 'nowhere',
    [rtnl.RT_SCOPE_HOST] = 'host',
    [rtnl.RT_SCOPE_LINK] = 'link',
    [rtnl.RT_SCOPE_SITE] = 'site'
}

local function do_address(action, dev, addr)
    local dev_index = socket.if_nametoindex(dev)
    if not dev_index then
        return nil, 'no such device'
    end

    local family = socket.AF_INET

    local local_addr = addr.address
    local prefix = addr.prefix

    if local_addr:find('/') then
        local_addr, prefix = local_addr:match('(%d+%.%d+%.%d+%.%d+)/(%d+)')
        if not local_addr then
            return nil, 'invalid local address'
        end
    end

    prefix = tonumber(prefix or 32)

    if prefix > 32 then
        return nil, 'invalid prefix length'
    end

    local local_addr = socket.inet_pton(family, local_addr)
    if not local_addr then
        return nil, 'invalid local address'
    end

    local scope = rtnl.RT_SCOPE_UNIVERSE

    if addr.scope then
        if not rtscope_to_num[addr.scope] then
            return nil, 'invalid scope'
        end
        scope = rtscope_to_num[addr.scope]
    end

    local msg_type

    if action == 'add' then
        msg_type = rtnl.RTM_NEWADDR
    elseif action == 'del' then
        msg_type = rtnl.RTM_DELADDR
    else
        error('invalid action')
    end

    local msg = nl.nlmsg(msg_type, nl.NLM_F_REQUEST | nl.NLM_F_ACK)

    msg:put(rtnl.ifaddrmsg({
        family = family,
        index = dev_index,
        prefixlen = prefix,
        scope = scope
    }))

    msg:put_attr(rtnl.IFA_LOCAL, local_addr)

    if addr.broadcast then
        local in_addr = socket.inet_pton(family, addr.broadcast)
        if not in_addr then
            return nil, 'invalid broadcast address'
        end
        msg:put_attr(rtnl.IFA_BROADCAST, in_addr)
    end

    if addr.label then
        msg:put_attr_str(rtnl.IFA_LABEL, addr.label)
    end

    if addr.metric then
        msg:put_attr_u32(rtnl.IFA_RT_PRIORITY, addr.metric)
    end

    if addr.priority then
        msg:put_attr_u32(rtnl.IFA_RT_PRIORITY, addr.priority)
    end

    return rtnl_send(msg)
end

function address.add(dev, addr)
    return do_address('add', dev, addr)
end

function address.del(dev, addr)
    return do_address('del', dev, addr)
end

function address.get(dev)
    local dev_index

    if dev then
        dev_index = socket.if_nametoindex(dev)
        if not dev_index then
            return nil, 'no such device'
        end
    end

    local sock, err = nl.open(nl.NETLINK_ROUTE)
    if not sock then
        return nil, err
    end

    local msg = nl.nlmsg(rtnl.RTM_GETADDR, nl.NLM_F_REQUEST | nl.NLM_F_DUMP)

    msg:put(rtnl.ifaddrmsg({ family = socket.AF_UNSPEC }))

    local ok, err = sock:send(msg)
    if not ok then
        return nil, err
    end

    local reses = {}

    while true do
        msg, err = sock:recv()
        if not msg then
            return nil, err
        end

        while true do
            local nlh = msg:next()
            if not nlh then
                break
            end

            if nlh.type == rtnl.RTM_NEWADDR then
                local res = {}

                local info = rtnl.parse_ifaddrmsg(msg)
                local family = info.family

                if not dev_index or dev_index == info.index then
                    res.ifname = socket.if_indextoname(info.index)
                    res.scope = rtscope_to_name[info.scope]
                    res.family = family

                    local attrs = msg:parse_attr(rtnl.IFADDRMSG_SIZE)
                    local addr_attr

                    if family == socket.AF_INET then
                        addr_attr = attrs[rtnl.IFA_LOCAL]
                    elseif family == socket.AF_INET6 then
                        addr_attr = attrs[rtnl.IFA_ADDRESS]
                    end

                    if addr_attr then
                        res.address = socket.inet_ntop(family, nl.attr_get_payload(addr_attr))

                        if attrs[rtnl.IFA_BROADCAST] then
                            res.broadcast = socket.inet_ntop(family, nl.attr_get_payload(attrs[rtnl.IFA_BROADCAST]))
                        end

                        if attrs[rtnl.IFA_LABEL] then
                            res.label = nl.attr_get_str(attrs[rtnl.IFA_LABEL])
                        end

                        reses[#reses + 1] = res
                    end
                end
            elseif nlh.type == nl.NLMSG_ERROR then
                err = msg:parse_error()
                if err < 0 then
                    return nil, 'RTNETLINK answers: ' .. sys.strerror(-err)
                end
            elseif nlh.type == nl.NLMSG_DONE then
                if dev_index and #reses < 1 then
                    return nil, 'not found'
                end
                return reses
            end
        end
    end
end

M.address = address

return M
