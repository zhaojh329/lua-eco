-- SPDX-License-Identifier: MIT
-- Author: Jianhui Zhao <zhaojh329@gmail.com>

--- SSH support (libssh2).
--
-- This module provides a coroutine-friendly SSH client session with helpers for:
--
-- - executing a remote command
-- - SCP receive/send (string or file)
--
-- The underlying implementation uses non-blocking libssh2 calls. When libssh2
-- returns `EAGAIN`, the current coroutine yields until the socket becomes
-- readable/writable.
--
-- Note: currently only **password authentication** is attempted (when the
-- server advertises it). Other auth methods (public key, agent, keyboard-
-- interactive) are not handled by this Lua wrapper.
--
-- @module eco.ssh

local ssh = require 'eco.internal.ssh'
local socket = require 'eco.socket'
local file = require 'eco.file'
local time = require 'eco.time'
local sys = require 'eco.sys'
local eco = require 'eco'

local M = {}

local COOPERATIVE_SLEEP_EVERY_LOOPS = 20
local COOPERATIVE_SLEEP_DELAY = 0.001

local function waitsocket(session, timeout)
    local dir = session.session:block_directions()
    local ev = 0

    if dir & ssh.SESSION_BLOCK_INBOUND then
        ev = ev | eco.READ
    end

    if dir & ssh.SESSION_BLOCK_OUTBOUND then
        ev = ev | eco.WRITE
    end

    return session.io:wait(ev, timeout)
end

local function channel_xfer_loop(session, deadline, wait_timeout, step, on_value)
    local loops = 0

    while true do
        if deadline and sys.uptime() >= deadline then
            return nil, 'timeout'
        end

        local value, err = step()
        if value == nil then
            if err ~= ssh.ERROR_EAGAIN then
                return nil, session.session:last_error()
            end

            local wt

            if deadline then
                wt = deadline - sys.uptime()
                if wt <= 0 then
                    return nil, 'timeout'
                end
            else
                wt = wait_timeout
            end

            if not waitsocket(session, wt) then
                return nil, 'timeout'
            end

            loops = 0
        else
            local done, on_err = on_value(value)
            if done == nil then
                return nil, on_err
            end

            if done then
                return true
            end

            loops = loops + 1

            if loops > COOPERATIVE_SLEEP_EVERY_LOOPS then
                loops = 0
                time.sleep(COOPERATIVE_SLEEP_DELAY)
            end
        end
    end
end

local function open_channel(session)
    local channel, err

    while true do
        channel, err = session.session:open_channel()
        if channel then break end

        if session.session:last_errno() ~= ssh.ERROR_EAGAIN then
            return nil, err
        end

        if not waitsocket(session, 5.0) then
            return nil, 'timeout'
        end
    end

    return channel
end

local function channel_scp_recv(session, source)
    local channel, size

    while true do
        channel, size = session.session:scp_recv(source)
        if channel then break end

        if session.session:last_errno() ~= ssh.ERROR_EAGAIN then
            return nil, size
        end

        if not waitsocket(session, 5.0) then
            return nil, 'timeout'
        end
    end

    return channel, size
end

local function channel_scp_send(session, dest, mode, size)
    local channel, err

    while true do
        channel, err = session.session:scp_send(dest, mode, size)
        if channel then break end

        if session.session:last_errno() ~= ssh.ERROR_EAGAIN then
            return nil, err
        end

        if not waitsocket(session, 5.0) then
            return nil, 'timeout'
        end
    end

    return channel
end

local function channel_call_c_wrap(session, channel, timeout, func, ...)
    timeout = timeout or 5.0

    local deadtime = sys.uptime() + timeout

    while sys.uptime() < deadtime do
        local ok, err = channel[func](channel, ...)
        if ok then return true end

        if err ~= ssh.ERROR_EAGAIN then
            return nil, session.session:last_error()
        end

        if not waitsocket(session, deadtime - sys.uptime()) then
            return nil, 'timeout'
        end
    end

    return nil, 'timeout'
end

local function channel_exec(session, channel, cmd)
    return channel_call_c_wrap(session, channel, nil, 'exec', cmd)
end

local function channel_close(session, channel)
    return channel_call_c_wrap(session, channel, nil, 'close')
end

local function channel_free(session, channel)
    return channel_call_c_wrap(session, channel, nil, 'free')
end

local function channel_send_eof(session, channel)
    return channel_call_c_wrap(session, channel, nil, 'send_eof')
end

local function channel_wait_eof(session, channel)
    return channel_call_c_wrap(session, channel, nil, 'wait_eof')
end

local function channel_wait_closed(session, channel)
    return channel_call_c_wrap(session, channel, nil, 'wait_closed')
end

local function channel_signal(session, channel, signame)
    return channel_call_c_wrap(session, channel, nil, 'signal', signame)
end

local function channel_exec_read_data(session, channel, stream_id, data, timeout)
    timeout = timeout or 30.0

    local deadtime = sys.uptime() + timeout

    return channel_xfer_loop(session, deadtime, nil,
        function()
            return channel:read(stream_id)
        end,
        function(chunk)
            if #chunk == 0 then
                return true
            end

            data[#data + 1] = chunk
            return false
        end
    )
end

--- SSH session object.
--
-- Instances are returned by @{ssh.new}. The object supports the Lua 5.4 `<close>`
-- attribute (calls @{session:free} automatically).
--
-- @type session
local session_methods = {}

--- Execute a command on the remote host.
--
-- The returned output is a concatenation of stdout and stderr.
--
-- @function session:exec
-- @tparam string cmd Command string.
-- @tparam[opt] number timeout Timeout in seconds for reading output.
-- @treturn string Command output (stdout+stderr).
-- @treturn int Exit status code.
-- @treturn string Exit signal name (or nil).
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
-- @usage
-- local ssh = require 'eco.ssh'
-- local eco = require 'eco'
--
-- eco.run(function()
--     local session<close>, err = ssh.new('127.0.0.1', 22, 'root', 'password')
--     assert(session, err)
--
--     local out, code, signal = session:exec('uptime')
--     assert(out, code)
--     print('exit:', code, 'signal:', signal)
--     print(out)
-- end)
--
-- eco.loop()
function session_methods:exec(cmd, timeout)
    local channel, err = open_channel(self)
    if not channel then
        return nil, err
    end

    local ok, err = channel_exec(self, channel, cmd)
    if not ok then
        channel_free(self, channel)
        return nil, err
    end

    local data = {}

    ok, err = channel_exec_read_data(self, channel, 0, data, timeout)
    if not ok then
        channel_signal(self, channel, 'KILL')
        channel_free(self, channel)
        return nil, err
    end

    channel_exec_read_data(self, channel, ssh.EXTENDED_DATA_STDERR, data, timeout)

    ok, err = channel_close(self, channel)
    if not ok then
        channel_free(self, channel)
        return nil, err
    end

    local exitcode = channel:get_exit_status()
    local exitsignal = channel:get_exit_signal()

    channel_free(self, channel)

    local signals = { HUP = 1, INT = 2, QUIT = 3, ILL = 4, TRAP = 5, ABRT = 6,
        BUS = 7, FPE = 8, KILL = 9, USR1 = 10, SEGV = 11, USR2 = 12, PIPE = 13,
        ALRM = 14, TERM = 15, STKFLT = 16, CHLD = 17,CONT = 18, STOP = 19,
        TSTP = 20, TTIN = 21, TTOU = 22, URG = 23, XCPU = 24, XFSZ = 25,
        VTALRM = 26, PROF = 27, WINCH = 28, POLL = 29, PWR = 30, SYS = 31
    }

    if exitsignal then
        exitcode = 128 + signals[exitsignal]
    end

    return table.concat(data), exitcode, exitsignal
end

local function scp_recv(session, channel, size, f, data)
    local got = 0

    local ok, err = channel_xfer_loop(session, nil, 3.0,
        function()
            return channel:read(0)
        end,
        function(chunk)
            if f then
                local ok, err = f:write(chunk)
                if not ok then
                    return nil, err
                end
            else
                data[#data + 1] = chunk
            end

            got = got + #chunk
            return got >= size
        end
    )

    if not ok then
        return nil, err
    end

    return got
end

--- Receive a remote file via SCP.
--
-- If `dest` is provided, the remote file will be stored to that local path and
-- this method returns the number of bytes written.
--
-- If `dest` is omitted, the whole file content is returned as a Lua string.
--
-- @function session:scp_recv
-- @tparam string source Remote file path.
-- @tparam[opt] string dest Local destination file path.
-- @treturn any result When `dest` is not provided: file content (string).
-- When `dest` is provided: bytes written (int).
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
-- @usage
-- local ssh = require 'eco.ssh'
-- local eco = require 'eco'
--
-- eco.run(function()
--     local session<close> = assert(ssh.new('127.0.0.1', 22, 'root', 'password'))
--     local data = assert(session:scp_recv('/etc/os-release'))
--     print(data)
--     assert(session:scp_recv('/etc/os-release', '/tmp/os-release'))
-- end)
--
-- eco.loop()
function session_methods:scp_recv(source, dest)
    local channel, size = channel_scp_recv(self, source)
    if not channel then
        return nil, size
    end

    local data = {}
    local f, err

    if dest then
        f, err = io.open(dest, 'w')
        if not f then
            channel_free(self, channel)
            return nil, err
        end
    end

    local got, err = scp_recv(self, channel, size, f, data)

    if f then f:close() end

    channel_free(self, channel)

    if not got then
        return nil, err
    end

    if f then
        return got
    else
        return table.concat(data)
    end
end

local function scp_send_data(session, channel, data)
    local total = #data
    local written = 0

    return channel_xfer_loop(session, nil, 3.0,
        function()
            return channel:write(data:sub(written + 1))
        end,
        function(n)
            written = written + n
            return written >= total
        end
    )
end

--- Send data to the remote host via SCP.
--
-- Creates/overwrites `dest` on the remote host.
--
-- @function session:scp_send
-- @tparam string data Content to send.
-- @tparam string dest Remote destination file path.
-- @treturn boolean true On success.
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
-- @usage
-- local ok, err = session:scp_send('hello\n', '/tmp/hello')
-- assert(ok, err)
function session_methods:scp_send(data, dest)
    local channel, size = channel_scp_send(self, dest,
            file.S_IRUSR | file.S_IWUSR | file.S_IRGRP | file.S_IROTH, #data)
    if not channel then
        return nil, size
    end

    local ok, err = scp_send_data(self, channel, data)

    channel_send_eof(self, channel)
    channel_wait_eof(self, channel)
    channel_wait_closed(self, channel)
    channel_free(self, channel)

    if not ok then
        return nil, err
    end

    return true
end

--- Send a local file to the remote host via SCP.
--
-- @function session:scp_sendfile
-- @tparam string source Local file path.
-- @tparam string dest Remote destination file path.
-- @treturn boolean true On success.
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
function session_methods:scp_sendfile(source, dest)
    local st, err = file.stat(source)
    if not st then
        return nil, err
    end

    if st['type'] ~= 'REG' then
        return nil, source .. ': not a regular file'
    end

    local channel, size = channel_scp_send(self, dest, st.mode, st.size)
    if not channel then
        return nil, size
    end

    local f, err = io.open(source)
    if not f then
        channel_free(self, channel)
        return nil, err
    end

    local ok = true
    local data

    while true do
        data, err = f:read(1024)
        if not data then break end

        ok, err = scp_send_data(self, channel, data)
        if not ok then break end
    end

    f:close()

    channel_send_eof(self, channel)
    channel_wait_eof(self, channel)
    channel_wait_closed(self, channel)
    channel_free(self, channel)

    if not ok then
        return nil, err
    end

    return true
end

--- Disconnect the SSH session.
--
-- @function session:disconnect
-- @tparam[opt] int reaason Disconnect reason code (libssh2 constant).
-- @tparam[opt] string description Disconnect description.
-- @treturn boolean true On success.
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
function session_methods:disconnect(reaason, description)
    self.disconnected = true

    local deadtime = sys.uptime() + 5.0

    reaason = reaason or ssh.DISCONNECT_BY_APPLICATION
    description = description or 'Normal Shutdown'

    while sys.uptime() < deadtime do
        local ok, err = self.session:disconnect(reaason, description)
        if ok then return true end

        if err ~= ssh.ERROR_EAGAIN then
            return nil, self.session:last_error()
        end

        if not waitsocket(self, deadtime - sys.uptime()) then
            return nil, 'timeout'
        end
    end

    return nil, 'timeout'
end

--- Close and free the session.
--
-- This is also used as the `__gc` and `__close` metamethod.
--
-- @function session:free
function session_methods:free()
    if not self.disconnected then
        self:disconnect()
    end

    local deadtime = sys.uptime() + 5.0

    while sys.uptime() < deadtime do
        local ok, err = self.session:free()
        if ok then break end

        if err ~= ssh.ERROR_EAGAIN then
            break
        end

        if not waitsocket(self, deadtime - sys.uptime()) then
            break
        end
    end

    self.sock:close()
end

--- End of `session` class section.
-- @section end

local session_metatable = {
    __index = session_methods,
    __gc = session_methods.free,
    __close = session_methods.free
}

--- Create a new SSH session.
--
-- This call:
--
-- 1. connects to the remote TCP endpoint
-- 2. performs SSH handshake
-- 3. attempts password authentication if the server advertises it
--
-- @function new
-- @tparam string ipaddr Remote IP address (IPv4/IPv6).
-- @tparam int port Remote port.
-- @tparam string username Username.
-- @tparam[opt] string password Password (used when password auth is supported).
-- @treturn session Session object.
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
function M.new(ipaddr, port, username, password)
    if not socket.is_ipv4_address(ipaddr) and not socket.is_ipv6_address(ipaddr) then
        return nil, 'invalid ipaddr: ' .. ipaddr
    end

    local sock, err = socket.connect_tcp(ipaddr, port)
    if not sock then
        return nil, err
    end

    local session = ssh.new()
    local fd = sock:getfd()

    local obj = { session = session, sock = sock, io = eco.io(fd) }

    local ok

    while true do
        ok, err = session:handshake(fd)
        if ok then break end

        if err ~= ssh.ERROR_EAGAIN then
            err = session:last_error()
            return nil, err
        end

        if not waitsocket(obj, 5.0) then
            return nil, 'handshake timeout'
        end
    end

    local userauth_list

    while true do
        userauth_list, err = session:userauth_list(username)
        if userauth_list or err == '' then break end

        if session:last_errno() ~= ssh.ERROR_EAGAIN then
            return nil, err
        end

        if not waitsocket(obj, 5.0) then
            return nil, 'userauth_list timeout'
        end
    end

    if userauth_list and userauth_list:match('password') then
        while true do
            ok, err = session:userauth_password(username, password)
            if ok then break end

            if err ~= ssh.ERROR_EAGAIN then
                err = session:last_error()
                return nil, err
            end

            if not waitsocket(obj, 5.0) then
                return nil, 'authentication timeout'
            end
        end
    end

    return setmetatable(obj, session_metatable)
end

return M
