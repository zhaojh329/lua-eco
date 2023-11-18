-- SPDX-License-Identifier: MIT
-- Author: Jianhui Zhao <zhaojh329@gmail.com>

local file = require 'eco.core.file'
local sys = require 'eco.core.sys'
local bufio = require 'eco.bufio'

local concat = table.concat

local M = {}

local exec_methods = {}

function exec_methods:release()
    if not self.stdout_fd then
        return
    end

    file.close(self.stdout_fd)
    file.close(self.stderr_fd)

    self.stdout_fd = nil
    self.stderr_fd = nil
end

function exec_methods:wait(timeout)
    return self.child_w:wait(timeout or 30.0)
end

function exec_methods:pid()
    return self.__pid
end

local function exec_read(b, pattern, timeout)
    if type(pattern) == 'number' then
        if pattern <= 0 then return '' end
        return b:read(pattern, timeout)
    end

    if pattern and pattern:sub(1, 1) == '*' then
        pattern = pattern:sub(2)
    end

    if pattern == 'a' then
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

    if not pattern then
        pattern = 'l'
    end

    if pattern == 'l' or pattern == 'L' then
        return b:readline(timeout, pattern == 'L')
    end

    error('invalid pattern:' .. tostring(pattern))
end

function exec_methods:read_stdout(pattern, timeout)
    if not self.stdout_fd then
        return nil, 'closeed'
    end

    return exec_read(self.stdout_b, pattern, timeout)
end

function exec_methods:read_stderr(pattern, timeout)
    if not self.stderr_fd then
        return nil, 'closeed'
    end

    return exec_read(self.stderr_b, pattern, timeout)
end

local exec_metatable = {
    __index = exec_methods,
    __gc = exec_methods.release
}

function M.exec(...)
    local pid, stdout_fd, stderr_fd = sys.exec(...)
    if not pid then
        return nil, stdout_fd
    end

    return setmetatable({
        __pid = pid,
        stdout_fd = stdout_fd,
        stderr_fd = stderr_fd,
        child_w = eco.watcher(eco.CHILD, pid),
        stdout_b = bufio.new({ w = eco.watcher(eco.IO, stdout_fd) }),
        stderr_b = bufio.new({ w = eco.watcher(eco.IO, stderr_fd) })
    }, exec_metatable)
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
