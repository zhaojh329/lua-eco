-- SPDX-License-Identifier: MIT
-- Author: Jianhui Zhao <zhaojh329@gmail.com>

local ssh = require 'eco.internal.ssh'
local socket = require 'eco.socket'
local file = require 'eco.file'
local time = require 'eco.time'
local sys = require 'eco.sys'
local eco = require 'eco'

local M = {}

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

    while sys.uptime() < deadtime do
        local chunk, err = channel:read(stream_id)
        if not chunk then
            if err ~= ssh.ERROR_EAGAIN then
                return nil, session.session:last_error()
            end

            if not waitsocket(session, deadtime - sys.uptime()) then
                return nil, 'timeout'
            end
        else
            if #chunk == 0 then return true end

            data[#data + 1] = chunk

            -- Avoid blocking for too long while receive too much
            time.sleep(0.0001)
        end
    end

    return nil, 'timeout'
end

local session_methods = {}

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

    local ok, err = channel_close(self, channel)
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

    while got < size do
        local chunk, err = channel:read(0)
        if not chunk then
            if err ~= ssh.ERROR_EAGAIN then
                return nil, session.session:last_error()
            end

            if not waitsocket(session, 3.0) then
                return nil, 'timeout'
            end
        else
            if f then
                local ok, err = f:write(chunk)
                if not ok then
                    return nil, err
                end
            else
                data[#data + 1] = chunk
            end

            got = got + #chunk

            -- Avoid blocking for too long while receive large file
            time.sleep(0.0001)
        end
    end

    return got
end

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

    while written < total do
        local n, err = channel:write(data:sub(written + 1))
        if not n then
            if err ~= ssh.ERROR_EAGAIN then
                return nil, session:last_error()
            end

            if not waitsocket(session, 3.0) then
                return nil, 'timeout'
            end
        else
            written = written + n
            -- Avoid blocking for too long while receive large file
            time.sleep(0.0001)
        end
    end

    return true
end

function session_methods:scp_send(data, dest)
    local channel, size = channel_scp_send(self, dest, file.S_IRUSR | file.S_IWUSR | file.S_IRGRP | file.S_IROTH, #data)
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

local session_metatable = {
    __index = session_methods,
    __gc = session_methods.free,
    __close = session_methods.free
}

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
