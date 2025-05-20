-- SPDX-License-Identifier: MIT
-- Author: Jianhui Zhao <zhaojh329@gmail.com>

local socket = require 'eco.socket'
local nl = require 'eco.core.nl'

local M = {}

local nl_methods = {}

function nl_methods:bind(groups, pid)
    local ok, err = self.sock:bind(groups, pid)
    if not ok then
        return nil, err
    end

    return true
end

function nl_methods:add_membership(group)
    return self.sock:setoption('netlink_add_membership', group)
end

function nl_methods:drop_membership(group)
    return self.sock:setoption('netlink_drop_membership', group)
end

function nl_methods:send(msg)
    return self.sock:send(msg:binary())
end

function nl_methods:recv(n, timeout)
    local data, err = self.sock:recv(n or 8192, timeout)
    if not data then
        return nil, err
    end

    return nl.nlmsg_ker(data)
end

function nl_methods:close()
    self.sock:close()
end

local metatable = {
    __index = nl_methods,
    __close = nl_methods.close
}

function M.open(protocol)
    local sock, err = socket.netlink(protocol)
    if not sock then
        return nil, err
    end

    return setmetatable({ sock = sock }, metatable)
end

return setmetatable(M, { __index = nl })
