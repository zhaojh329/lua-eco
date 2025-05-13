-- SPDX-License-Identifier: MIT
-- Author: Jianhui Zhao <zhaojh329@gmail.com>

local file = require 'eco.core.file'
local sys = require 'eco.core.sys'
local bufio = require 'eco.bufio'

local M = {}

local exec_methods = {}

function exec_methods:close()
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

function exec_methods:read_stdout(pattern, timeout)
    return self.stdout_b:read(pattern, timeout)
end

function exec_methods:read_stderr(pattern, timeout)
    return self.stderr_b:read(pattern, timeout)
end

local exec_metatable = {
    __index = exec_methods,
    __gc = exec_methods.close,
    __close = exec_methods.close
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
        stdout_b = bufio.new(stdout_fd),
        stderr_b = bufio.new(stderr_fd)
    }, exec_metatable)
end

-- stdout, stderr, err = sys.sh(cmd, timeout)
function M.sh(cmd, timeout)
    assert(type(cmd) == 'string' or type(cmd) == 'table', 'cmd must be a string or table')

    if type(cmd) == 'string' then
        cmd = { '/bin/sh', '-c', cmd }
    end

    local p<close>, err = M.exec(table.unpack(cmd))
    if not p then
        return nil, nil, err
    end

    local stdout, stderr

    timeout = timeout or 30

    stdout, err = p:read_stdout('*a', timeout)
    if not stdout then
        return nil, nil, err
    end

    stderr, err = p:read_stderr('*a', timeout)
    if not stderr then
        return stdout, nil, err
    end

    return stdout, stderr
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
