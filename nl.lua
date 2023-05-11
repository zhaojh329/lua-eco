-- SPDX-License-Identifier: MIT
-- Author: Jianhui Zhao <zhaojh329@gmail.com>

local socket = require 'eco.socket'
local nl = require 'eco.core.nl'
local file = require 'eco.file'
local sys = require 'eco.sys'

local M = {}

local nl_methods = {}

function nl_methods:bind(groups, pid)
    local mt = getmetatable(self)

    local ok, err = mt.sock:bind(groups, pid)
    if not ok then
        return nil, err
    end

    return true
end

function nl_methods:add_membership(group)
    local mt = getmetatable(self)
    return mt.sock:setoption('netlink_add_membership', group)
end

function nl_methods:drop_membership(group)
    local mt = getmetatable(self)
    return mt.sock:setoption('netlink_drop_membership', group)
end

function nl_methods:send(msg)
    local mt = getmetatable(self)
    return mt.sock:sendto(msg:binary())
end

function nl_methods:recv(n, timeout)
    local mt = getmetatable(self)

    local data, addr = mt.sock:recvfrom(n or 8192, timeout)
    if not data then
        return nil, addr
    end

    return nl.nlmsg_ker(data), addr
end

function nl_methods:close()
    local mt = getmetatable(self)
    mt.sock:close()
end

function M.open(protocol)
    local sock, err = socket.netlink(protocol)
    if not sock then
        return nil, 'create netlink socket fail: ' .. err
    end

    return setmetatable({}, {
        sock = sock,
        __index = nl_methods,
    })
end

return setmetatable(M, { __index = nl })
