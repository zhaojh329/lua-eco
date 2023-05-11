#!/usr/bin/env eco

local genl = require 'eco.genl'
local sys = require 'eco.sys'
local bit = require 'eco.bit'
local nl = require 'eco.nl'

local function parse_ops(nest)
    for _, ops in pairs(nl.parse_attr_nested(nest) or {}) do
        local attrs = nl.parse_attr_nested(ops) or {}
        if attrs[genl.CTRL_ATTR_OP_ID] then
            print('', 'id-0x' .. string.format('%x', nl.attr_get_u32(attrs[genl.CTRL_ATTR_OP_ID])))
        end
    end
end

local function parse_grps(nest)
    for _, ops in pairs(nl.parse_attr_nested(nest) or {}) do
        local attrs = nl.parse_attr_nested(ops) or {}

        local name = ''
        if attrs[genl.CTRL_ATTR_MCAST_GRP_NAME] then
            name = nl.attr_get_str(attrs[genl.CTRL_ATTR_MCAST_GRP_NAME])
        end

        if attrs[genl.CTRL_ATTR_MCAST_GRP_ID] then
            print('', 'id-0x' .. string.format('%x', nl.attr_get_u32(attrs[genl.CTRL_ATTR_MCAST_GRP_ID])), name)
        end
    end
end

local sock, err = nl.open(nl.NETLINK_GENERIC)
if not sock then
    print('open fail:', err)
    return
end

local msg = nl.nlmsg(genl.GENL_ID_CTRL, bit.bor(nl.NLM_F_REQUEST, nl.NLM_F_DUMP))

msg:put(genl.genlmsghdr({ cmd = genl.CTRL_CMD_GETFAMILY, version = 1 }))
msg:put_attr_u32(genl.CTRL_ATTR_FAMILY_ID, genl.GENL_ID_CTRL)

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

        if nlh.type == genl.GENL_ID_CTRL then
            --local info = genl.parse_genlmsghdr(msg)

            local attrs = msg:parse_attr(genl.GENLMSGHDR_SIZE)

            if attrs[genl.CTRL_ATTR_FAMILY_NAME] then
                print('family name:', nl.attr_get_str(attrs[genl.CTRL_ATTR_FAMILY_NAME]))
            end

            if attrs[genl.CTRL_ATTR_FAMILY_ID] then
                local family_id = nl.attr_get_u16(attrs[genl.CTRL_ATTR_FAMILY_ID])
                print('family id:', family_id)
            end

            if attrs[genl.CTRL_ATTR_VERSION] then
                local version = nl.attr_get_u32(attrs[genl.CTRL_ATTR_VERSION])
                print('version:', version)
            end

            if attrs[genl.CTRL_ATTR_HDRSIZE] then
                local hdrsize = nl.attr_get_u32(attrs[genl.CTRL_ATTR_HDRSIZE])
                print('hdrsize:', hdrsize)
            end

            if attrs[genl.CTRL_ATTR_MAXATTR] then
                local maxattr = nl.attr_get_u32(attrs[genl.CTRL_ATTR_MAXATTR])
                print('maxattr:', maxattr)
            end

            if attrs[genl.CTRL_ATTR_OPS] then
                print('ops:')
                parse_ops(attrs[genl.CTRL_ATTR_OPS])
            end

            if attrs[genl.CTRL_ATTR_MCAST_GROUPS] then
                print('grps:')
                parse_grps(attrs[genl.CTRL_ATTR_MCAST_GROUPS])
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
