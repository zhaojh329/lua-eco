-- SPDX-License-Identifier: MIT
-- Author: Jianhui Zhao <zhaojh329@gmail.com>

local socket = require 'eco.socket'
local nl = require 'eco.core.nl'
local sys = require 'eco.core.sys'

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

local function nl_error_message(on_error, errno)
    if on_error then
        return on_error(errno)
    end

    return 'netlink error: ' .. sys.strerror(errno)
end

local function nl_handle_error(reply, on_error)
    local nerr, err = reply:parse_error()
    if nerr == nil then
        return nil, err
    end

    if nerr < 0 then
        return nil, nl_error_message(on_error, -nerr)
    end

    return nerr
end

local function nl_receive_loop(self, on_msg, on_error, n, timeout, stop_on_done)
    while true do
        local reply, err = self:recv(n, timeout)
        if not reply then
            return nil, err
        end

        while true do
            local nlh = reply:next()
            if not nlh then
                break
            end

            if nlh.type == nl.NLMSG_ERROR then
                local nerr

                nerr, err = nl_handle_error(reply, on_error)
                if nerr == nil then
                    return nil, err
                end
            elseif nlh.type == nl.NLMSG_DONE and stop_on_done then
                return true
            elseif on_msg then
                local ok

                ok, err = on_msg(reply, nlh)

                if ok == true then
                    return true
                elseif ok == false then
                    return nil, err
                end
            end
        end
    end
end

function nl_methods:request_ack(msg, on_error)
    local ok, err = self:send(msg)
    if not ok then
        return nil, err
    end

    local reply

    reply, err = self:recv()
    if not reply then
        return nil, err
    end

    local nlh = reply:next()
    if not nlh then
        return nil, 'no ack'
    end

    if nlh.type ~= nl.NLMSG_ERROR then
        return nil, 'invalid msg received'
    end

    local nerr

    nerr, err = nl_handle_error(reply, on_error)
    if nerr == nil then
        return nil, err
    end

    if nerr == 0 then
        return true
    end

    return nil, 'invalid ack'
end

function nl_methods:request_dump(msg, on_msg, on_error)
    local ok, err = self:send(msg)
    if not ok then
        return nil, err
    end

    return nl_receive_loop(self, on_msg, on_error, nil, nil, true)
end

function nl_methods:recv_messages(on_msg, on_error, n, timeout)
    return nl_receive_loop(self, on_msg, on_error, n, timeout, false)
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
