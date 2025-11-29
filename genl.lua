-- SPDX-License-Identifier: MIT
-- Author: Jianhui Zhao <zhaojh329@gmail.com>

local genl = require 'eco.internal.genl'
local sys = require 'eco.sys'
local nl = require 'eco.nl'

local M = {}

local cache = {}

local function parse_grps(nest, groups)
    for _, grp in pairs(nl.parse_attr_nested(nest) or {}) do
        local attrs = nl.parse_attr_nested(grp)
        groups[nl.attr_get_str(attrs[genl.CTRL_ATTR_MCAST_GRP_NAME])] = nl.attr_get_u32(attrs[genl.CTRL_ATTR_MCAST_GRP_ID])
    end
end

local function __get_family_by(sock, params)
    local msg = nl.nlmsg(genl.GENL_ID_CTRL, nl.NLM_F_REQUEST)

    msg:put(genl.genlmsghdr({ cmd = genl.CTRL_CMD_GETFAMILY }))

    if params.id then
        msg:put_attr_u16(genl.CTRL_ATTR_FAMILY_ID, params.id)
    else
        msg:put_attr_strz(genl.CTRL_ATTR_FAMILY_NAME, params.name)
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
        return nil, 'no msg responsed'
    end

    if nlh.type == nl.NLMSG_ERROR then
        err = msg:parse_error()
        return nil, sys.strerror(-err)
    end

    local attrs = msg:parse_attr(genl.GENLMSGHDR_SIZE)
    local info = {groups = {}}

    info.name = nl.attr_get_str(attrs[genl.CTRL_ATTR_FAMILY_NAME])
    info.id = nl.attr_get_u16(attrs[genl.CTRL_ATTR_FAMILY_ID])
    info.version = nl.attr_get_u32(attrs[genl.CTRL_ATTR_VERSION])
    info.hdrsize = nl.attr_get_u32(attrs[genl.CTRL_ATTR_HDRSIZE])
    info.maxattr = nl.attr_get_u32(attrs[genl.CTRL_ATTR_MAXATTR])

    if attrs[genl.CTRL_ATTR_MCAST_GROUPS] then
        parse_grps(attrs[genl.CTRL_ATTR_MCAST_GROUPS], info.groups)
    end

    cache[info.id] = info
    cache[info.name] = info

    return info
end

local function get_family_by(params)
    local sock<close>, err = nl.open(nl.NETLINK_GENERIC)
    if not sock then
        return nil, err
    end

    return __get_family_by(sock, params)
end

function M.get_family_byid(id)
    if type(id) ~= 'number' then
        error('invalid id')
    end

    if cache[id] then
        return cache[id]
    end

    return get_family_by({ id = id })
end

function M.get_family_byname(name)
    if type(name) ~= 'string' then
        error('invalid name')
    end

    if cache[name] then
        return cache[name]
    end

    return get_family_by({ name = name })
end

function M.get_family_id(name)
    if type(name) ~= 'string' then
        error('invalid name')
    end

    if cache[name] then
        return cache[name].id
    end

    local info, err = get_family_by({ name = name })
    if not info then
        return nil, err
    end

    return info.id
end

function M.get_group_id(family, group)
    if type(family) ~= 'string' then
        error('invalid family name')
    end

    if type(group) ~= 'string' then
        error('invalid group name')
    end

    if cache[family] then
        return cache[family].groups[group]
    end

    local info, err = get_family_by({ name = family })
    if not info then
        return nil, err
    end

    return info.groups[group]
end

return setmetatable(M, { __index = genl })
