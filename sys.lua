-- SPDX-License-Identifier: MIT
-- Author: Jianhui Zhao <zhaojh329@gmail.com>

local file = require 'eco.internal.file'
local sys = require 'eco.internal.sys'
local bufio = require 'eco.bufio'
local sync = require 'eco.sync'
local eco = require 'eco'

local M = {}

local childs = {}

local function sigchld_cb()
    local pid, status = sys.waitpid(-1)
    if not pid then
        return
    end

    local c = childs[pid]
    if not c then
        return
    end

    childs[pid] = nil

    c:signal({ pid = pid, status = status })
end

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
    local c = sync.cond()

    childs[self.__pid] = c

    local res, err = c:wait(timeout)
    if not res then
        return nil, err
    end

    return res.pid, res.status
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

-- p, err = sys.exec(cmd, arg1, arg2)
-- p, err = sys.exec({ cmd, arg1, arg2 }, { a = 1, b = 2 })
function M.exec(...)
    local pid, stdout_fd, stderr_fd = sys.exec(...)
    if not pid then
        return nil, stdout_fd
    end

    return setmetatable({
        __pid = pid,
        stdout_fd = stdout_fd,
        stderr_fd = stderr_fd,
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
    local sfd, err = sys.signalfd(sig)
    if not sfd then
        return nil, err
    end

    local rd = eco.reader(sfd)

    eco.run(function(...)
        while true do
            local si = rd:read(128)
            if not si then
                file.close(sfd)
                return
            end

            local signo = string.unpack('I4', si)
            if signo == sig then
                cb(...)
            end
        end
    end, ...)

    return rd
end

M.signal(sys.SIGCHLD, sigchld_cb)

return setmetatable(M, { __index = sys })
