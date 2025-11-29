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
-- @module eco.nl
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

local socket = require 'eco.socket'
local nl = require 'eco.internal.nl'

local M = {
    --- Netlink message type: no-op.
    NLMSG_NOOP = nl.NLMSG_NOOP,
    --- Netlink message type: error.
    NLMSG_ERROR = nl.NLMSG_ERROR,
    --- Netlink message type: end of multipart message.
    NLMSG_DONE = nl.NLMSG_DONE,
    --- Netlink message type: data lost.
    NLMSG_OVERRUN = nl.NLMSG_OVERRUN,

    --- Minimum reserved control message type.
    NLMSG_MIN_TYPE = nl.NLMSG_MIN_TYPE,

    --- Netlink message flag: request.
    NLM_F_REQUEST = nl.NLM_F_REQUEST,
    --- Netlink message flag: multipart message.
    NLM_F_MULTI = nl.NLM_F_MULTI,
    --- Netlink message flag: request ACK.
    NLM_F_ACK = nl.NLM_F_ACK,
    --- Netlink message flag: echo request.
    NLM_F_ECHO = nl.NLM_F_ECHO,
    --- Netlink message flag: dump interrupted.
    NLM_F_DUMP_INTR = nl.NLM_F_DUMP_INTR,
    --- Netlink message flag: dump filtered.
    NLM_F_DUMP_FILTERED = nl.NLM_F_DUMP_FILTERED,
    --- Netlink message flag: dump all roots.
    NLM_F_ROOT = nl.NLM_F_ROOT,
    --- Netlink message flag: return all matches.
    NLM_F_MATCH = nl.NLM_F_MATCH,
    --- Netlink message flag: atomic dump.
    NLM_F_ATOMIC = nl.NLM_F_ATOMIC,
    --- Netlink message flag: dump (typically `ROOT|MATCH`).
    NLM_F_DUMP = nl.NLM_F_DUMP,
    --- Netlink message flag: replace existing object.
    NLM_F_REPLACE = nl.NLM_F_REPLACE,
    --- Netlink message flag: don't touch if it exists.
    NLM_F_EXCL = nl.NLM_F_EXCL,
    --- Netlink message flag: create if it doesn't exist.
    NLM_F_CREATE = nl.NLM_F_CREATE,
    --- Netlink message flag: append to end of list.
    NLM_F_APPEND = nl.NLM_F_APPEND,
    --- Netlink message flag: do not recurse.
    NLM_F_NONREC = nl.NLM_F_NONREC,
    --- Netlink message flag: capped dump.
    NLM_F_CAPPED = nl.NLM_F_CAPPED,
    --- Netlink message flag: include ACK TLVs.
    NLM_F_ACK_TLVS = nl.NLM_F_ACK_TLVS,

    --- Extended ACK attribute: human-readable error message.
    NLMSGERR_ATTR_MSG = nl.NLMSGERR_ATTR_MSG,
    --- Extended ACK attribute: offset of the error.
    NLMSGERR_ATTR_OFFS = nl.NLMSGERR_ATTR_OFFS,
    --- Extended ACK attribute: cookie (opaque identifier).
    NLMSGERR_ATTR_COOKIE = nl.NLMSGERR_ATTR_COOKIE,

    --- Netlink protocol family: routing/device hooks.
    NETLINK_ROUTE = nl.NETLINK_ROUTE,
    --- Netlink protocol family: unused.
    NETLINK_UNUSED = nl.NETLINK_UNUSED,
    --- Netlink protocol family: userspace socket.
    NETLINK_USERSOCK = nl.NETLINK_USERSOCK,
    --- Netlink protocol family: firewall.
    NETLINK_FIREWALL = nl.NETLINK_FIREWALL,
    --- Netlink protocol family: socket monitoring/diagnostics.
    NETLINK_SOCK_DIAG = nl.NETLINK_SOCK_DIAG,
    --- Netlink protocol family: netfilter/ulog.
    NETLINK_NFLOG = nl.NETLINK_NFLOG,
    --- Netlink protocol family: IPsec.
    NETLINK_XFRM = nl.NETLINK_XFRM,
    --- Netlink protocol family: SELinux event notifications.
    NETLINK_SELINUX = nl.NETLINK_SELINUX,
    --- Netlink protocol family: iSCSI.
    NETLINK_ISCSI = nl.NETLINK_ISCSI,
    --- Netlink protocol family: auditing.
    NETLINK_AUDIT = nl.NETLINK_AUDIT,
    --- Netlink protocol family: FIB lookup.
    NETLINK_FIB_LOOKUP = nl.NETLINK_FIB_LOOKUP,
    --- Netlink protocol family: kernel connector.
    NETLINK_CONNECTOR = nl.NETLINK_CONNECTOR,
    --- Netlink protocol family: netfilter.
    NETLINK_NETFILTER = nl.NETLINK_NETFILTER,
    --- Netlink protocol family: IPv6 firewall.
    NETLINK_IP6_FW = nl.NETLINK_IP6_FW,
    --- Netlink protocol family: DECnet routing messages.
    NETLINK_DNRTMSG = nl.NETLINK_DNRTMSG,
    --- Netlink protocol family: kernel uevents.
    NETLINK_KOBJECT_UEVENT = nl.NETLINK_KOBJECT_UEVENT,
    --- Netlink protocol family: generic netlink.
    NETLINK_GENERIC = nl.NETLINK_GENERIC,
}

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
function M.open(protocol)
    local sock, err = socket.netlink(protocol)
    if not sock then
        return nil, err
    end

    return setmetatable({ sock = sock }, metatable)
end

return setmetatable(M, { __index = nl })
