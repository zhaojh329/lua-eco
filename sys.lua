-- SPDX-License-Identifier: MIT
-- Author: Jianhui Zhao <zhaojh329@gmail.com>

local file = require 'eco.core.file'
local sys = require 'eco.core.sys'
local bufio = require 'eco.bufio'

local concat = table.concat
local type = type

local M = {}

local exec_methods = {}

function exec_methods:release()
    local mt = getmetatable(self)

    if not mt.stdout_fd then
        return
    end

    file.close(mt.stdout_fd)
    file.close(mt.stderr_fd)

    mt.stdout_fd = nil
    mt.stderr_fd = nil
end

function exec_methods:wait(timeout)
    local mt = getmetatable(self)
    return mt.child_w:wait(timeout or 30.0)
end

function exec_methods:pid()
    local mt = getmetatable(self)
    return mt.pid
end

local function exec_read(b, pattern, timeout)
    if type(pattern) == 'number' then
        if pattern <= 0 then return '' end
        return b:read(pattern, timeout)
    end

    if pattern == '*a' then
        local data = {}
        local chunk, err
        while true do
            chunk, err = b:read(4096)
            if not chunk then break end
            data[#data + 1] = chunk
        end

        if #data == 0 then
            return nil, err
        end

        if err == 'closed' then
            return concat(data)
        end

        return nil, err, concat(data)
    end

    if not pattern or pattern == '*l' then
        return b:readline(timeout)
    end

    error('invalid pattern:' .. tostring(pattern))
end

function exec_methods:read_stdout(pattern, timeout)
    local mt = getmetatable(self)

    if not mt.stdout_fd then
        return nil, 'closeed'
    end

    return exec_read(mt.stdout_b, pattern, timeout)
end

function exec_methods:read_stderr(pattern, timeout)
    local mt = getmetatable(self)

    if not mt.stderr_fd then
        return nil, 'closeed'
    end

    return exec_read(mt.stderr_b, pattern, timeout)
end

function M.exec(...)
    local pid, stdout_fd, stderr_fd = sys.exec(...)
    if not pid then
        return nil, stdout_fd
    end

    return setmetatable({}, {
        pid = pid,
        stdout_fd = stdout_fd,
        stderr_fd = stderr_fd,
        child_w = eco.watcher(eco.CHILD, pid),
        stdout_b = bufio.new({ w = eco.watcher(eco.IO, stdout_fd) }),
        stderr_b = bufio.new({ w = eco.watcher(eco.IO, stderr_fd) }),
        __index = exec_methods,
        __gc = exec_methods.release
    })
end

function M.signal(sig, cb, ...)
    local w = eco.watcher(eco.SIGNAL, sig)

    eco.run(function(...)
        while true do
            if not w:wait() then return end
            cb(...)
        end
    end, ...)

    return w
end

return setmetatable(M, { __index = sys })
