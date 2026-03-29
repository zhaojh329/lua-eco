-- SPDX-License-Identifier: MIT
-- Author: Jianhui Zhao <zhaojh329@gmail.com>

--- Netlink sockets and helpers.
--
-- This module is a small wrapper around @{eco.socket}'s netlink sockets and
-- provides low-level message/attribute helpers and Linux netlink constants.
--
-- The most common entry point is @{nl.open}, which returns a socket object with
-- convenience methods.
--
-- Many constants from Linux headers are also exported:
--
-- - Netlink message type: `NLMSG_*`
-- - Netlink message flag: `NLM_F_*`
-- - Netlink protocol family: `NETLINK_*`
--
-- @module eco.nl

local socket = require 'eco.socket'
local nl = require 'eco.internal.nl'
local sys = require 'eco.internal.sys'

local M = {}

local nl_methods = {}

--- Netlink socket object returned by @{nl.open}.
--
-- This is a thin wrapper around a netlink socket returned by
-- @{eco.socket.netlink}. The object also supports Lua 5.4 to-be-closed
-- variables via the `__close` metamethod.
--
-- @type nlsocket

--- Bind the netlink socket.
--
-- @function nlsocket:bind
-- @tparam int groups Multicast group bitmap.
-- @tparam[opt] int pid Local PID to bind.
-- @treturn boolean true On success
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
function nl_methods:bind(groups, pid)
    local ok, err = self.sock:bind(groups, pid)
    if not ok then
        return nil, err
    end

    return true
end

--- Subscribe to a multicast group.
--
-- @function nlsocket:add_membership
-- @tparam int group Multicast group id.
-- @treturn boolean true On success
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
function nl_methods:add_membership(group)
    return self.sock:setoption('netlink_add_membership', group)
end

--- Unsubscribe from a multicast group.
--
-- @function nlsocket:drop_membership
-- @tparam int group Multicast group id.
-- @treturn boolean true On success
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
function nl_methods:drop_membership(group)
    return self.sock:setoption('netlink_drop_membership', group)
end

--- Send a netlink message.
--
-- @function nlsocket:send
-- @tparam nlmsg msg Message created by @{nl.nlmsg}.
-- @treturn int Bytes sent.
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
function nl_methods:send(msg)
    return self.sock:send(msg:binary())
end

--- Receive data from the netlink socket.
--
-- The return value is a message parser created by @{nl.nlmsg_ker}. The parser
-- may contain multiple netlink messages; iterate them with @{nlmsg_ker:next}.
--
-- @function nlsocket:recv
-- @tparam[opt=8192] integer n Max bytes to read.
-- @tparam[opt] number timeout Timeout in seconds.
-- @treturn nlmsg_ker
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
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

--- Send a request and wait for an ACK (`NLMSG_ERROR` with error=0).
--
-- @function nlsocket:request_ack
-- @tparam nlmsg msg Request message.
-- @tparam[opt] function on_error Optional mapper `on_error(errno)->string`.
-- @treturn boolean true On success.
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
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

--- Send a request and iterate reply messages until `NLMSG_DONE`.
--
-- Callback return conventions:
-- - `true`: stop early and return success
-- - `false, err`: stop and return error
-- - `nil`: continue
--
-- @function nlsocket:request_dump
-- @tparam nlmsg msg Request message.
-- @tparam[opt] function on_msg Callback `on_msg(reply, nlh)`.
-- @tparam[opt] function on_error Optional mapper `on_error(errno)->string`.
-- @treturn boolean true On success.
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
function nl_methods:request_dump(msg, on_msg, on_error)
    local ok, err = self:send(msg)
    if not ok then
        return nil, err
    end

    return nl_receive_loop(self, on_msg, on_error, nil, nil, true)
end

--- Receive and dispatch netlink messages in a loop.
--
-- This is intended for event subscription sockets that only receive
-- multicast notifications.
--
-- Callback return conventions:
-- - `true`: stop loop and return success
-- - `false, err`: stop loop and return error
-- - `nil`: continue
--
-- @function nlsocket:recv_messages
-- @tparam[opt] function on_msg Callback `on_msg(reply, nlh)`.
-- @tparam[opt] function on_error Optional mapper `on_error(errno)->string`.
-- @tparam[opt=8192] integer n Max bytes to read per recv.
-- @tparam[opt] number timeout Timeout in seconds for each recv.
-- @treturn boolean true When callback stops loop with `true`.
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
function nl_methods:recv_messages(on_msg, on_error, n, timeout)
    return nl_receive_loop(self, on_msg, on_error, n, timeout, false)
end

--- Close the socket.
--
-- @function nlsocket:close
function nl_methods:close()
    self.sock:close()
end

--- End of `nlsocket` class section.
-- @section end

local metatable = {
    __index = nl_methods,
    __close = nl_methods.close
}

--- Create a netlink socket.
--
-- @function open
-- @tparam int protocol Netlink protocol.
-- @treturn nlsocket
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
-- @usage
-- local nl = require 'eco.nl'
--
-- local sock<close>, err = nl.open(nl.NETLINK_ROUTE)
-- assert(sock, err)
--
-- -- Build a request.
-- local msg = nl.nlmsg(0, 0)
-- msg:put('hello')
-- assert(sock:send(msg))
--
-- -- Receive and iterate.
-- local rx = assert(sock:recv())
-- local hdr = rx:next()
-- if hdr then
--     print('type:', hdr.type)
-- end
function M.open(protocol)
    local sock, err = socket.netlink(protocol)
    if not sock then
        return nil, err
    end

    return setmetatable({ sock = sock }, metatable)
end

return setmetatable(M, { __index = nl })
