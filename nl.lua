-- SPDX-License-Identifier: MIT
-- Author: Jianhui Zhao <zhaojh329@gmail.com>

local socket = require 'eco.socket'
local nl = require 'eco.core.nl'

local M = {}

local nl_methods = {}

-- Set the timeout value in seconds for subsequent read operations
function nl_methods:settimeout(seconds)
    self.sock:settimeout(seconds)
end

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
    return self.sock:sendto(msg:binary())
end

function nl_methods:recv(n)
    local data, addr = self.sock:recvfrom(n or 8192)
    if not data then
        return nil, addr
    end

    return nl.nlmsg_ker(data), addr
end

function nl_methods:close()
    self.sock:close()
end

local metatable = { __index = nl_methods }

function M.open(protocol)
    local sock, err = socket.netlink(protocol)
    if not sock then
        return nil, 'create netlink socket fail: ' .. err
    end

    return setmetatable({ sock = sock }, metatable)
end

return setmetatable(M, { __index = nl })
