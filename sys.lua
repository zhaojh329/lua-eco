-- SPDX-License-Identifier: MIT
-- Author: Jianhui Zhao <zhaojh329@gmail.com>

--- System and process related utilities.
-- @module eco.sys

local file = require 'eco.internal.file'
local sys = require 'eco.internal.sys'
local bufio = require 'eco.bufio'
local sync = require 'eco.sync'
local eco = require 'eco'

local M = {
    --- Signal number for interrupt from keyboard.
    SIGINT = sys.SIGINT,
    --- Signal number for termination.
    SIGTERM = sys.SIGTERM,
    --- Signal number for terminal line hangup.
    SIGHUP = sys.SIGHUP
}

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

---
-- Process handle returned by @{exec}.
--
-- This object represents a running child process.
-- It provides methods for waiting, reading output.
--
-- @type process
local exec_methods = {}

---
-- Close stdout and stderr file descriptors.
--
-- @function process:close
function exec_methods:close()
    if not self.stdout_fd then
        return
    end

    file.close(self.stdout_fd)
    file.close(self.stderr_fd)

    self.stdout_fd = nil
    self.stderr_fd = nil
end

---
-- Wait for the process to exit.
--
-- @function process:wait
-- @tparam[opt] number timeout Timeout in seconds.
-- @treturn int pid Process id.
-- @treturn int status Exit status.
-- @treturn[2] nil On timeout or error.
-- @treturn[2] string Error message.
function exec_methods:wait(timeout)
    local c = sync.cond()

    childs[self.__pid] = c

    local res, err = c:wait(timeout)
    if not res then
        return nil, err
    end

    return res.pid, res.status
end

---
-- Get process id.
--
-- @function process:pid
-- @treturn int pid Child process id.
function exec_methods:pid()
    return self.__pid
end

---
-- Read from process stdout.
--
-- @function process:read_stdout
-- @tparam[opt='l'] string|int pattern Read pattern (same as file:read).
-- @tparam[opt] number timeout Timeout in seconds.
-- @treturn string|number data
-- @treturn[2] nil On timeout or EOF.
-- @treturn[2] string Error message.
function exec_methods:read_stdout(pattern, timeout)
    return self.stdout_b:read(pattern, timeout)
end

---
-- Read from process stderr.
--
-- @function process:read_stderr
-- @tparam[opt='l'] string|int pattern Read pattern.
-- @tparam[opt] number timeout Timeout in seconds.
-- @treturn string|number data
-- @treturn[2] nil On timeout or EOF.
-- @treturn[2] string Error message.
function exec_methods:read_stderr(pattern, timeout)
    return self.stderr_b:read(pattern, timeout)
end

--- End of `process` class section.
-- @section end

local exec_metatable = {
    __index = exec_methods,
    __gc = exec_methods.close,
    __close = exec_methods.close
}

---
-- Execute a program.
--
-- Spawns a new process and returns a process handle object.
-- The returned object provides methods to wait for process exit, read stdout/stderr.
--
-- There are two supported calling forms:
--
-- 1. Argument list form:
--
--        p, err = sys.exec(cmd, arg1, arg2, ...)
--
-- 2. Table form with optional environment:
--
--        p, err = sys.exec({ cmd, arg1, arg2, ... }, env)
--
-- In the second form, `env` is a table of environment variables.
--
-- @function exec
-- @tparam string|table cmd
--
--   - a string representing the program to execute, followed by arguments
--   - or a table `{ cmd, arg1, arg2, ... }`
-- @tparam[opt] table env Environment variables table (only valid when first argument is a table form).
--
-- @treturn process Process handle object on success.
--
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message when failed.
--
-- @usage
-- -- simple form
-- local p, err = sys.exec('ls', '-l', '/tmp')
-- if not p then
--     print(err)
-- end
--
-- -- table form with environment
-- local p, err = sys.exec({ 'printenv', 'A' }, { A = '123' })
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

---
-- Execute a shell command and return stdout and stderr.
--
-- This is a convenience wrapper around @{exec}.
-- It accepts a command string or a table of arguments.
-- If a string is provided, it will be executed using `/bin/sh -c`.
--
-- @function sh
-- @tparam string|table cmd Command to execute.
--
--   - If string, executed via `/bin/sh -c`.
--   - If table, first element is program, remaining are arguments.
-- @tparam[opt=30] number timeout Timeout in seconds for reading stdout/stderr.
--
-- @treturn[1] string Standard output of the command.
-- @treturn[1] string Standard error of the command.
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message when failed.
--
-- @usage
-- local out, err = sys.sh({ 'echo', 'hello' })
-- if not out then
--     print("Command failed:", e)
-- else
--     print("stdout:", out)
--     print("stderr:", err)
-- end
--
-- -- Table form with program and arguments
-- local out, err, e = sys.sh({ "ls", "-l", "/tmp" })
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

---
-- Spawn a new process to run a Lua function.
--
-- This function forks a child process and runs the given function `f`
-- inside it. The child process will be terminated if the parent dies (`PR_SET_PDEATHSIG = SIGKILL`).
--
-- @function spawn
-- @tparam function f Lua function to run in the child process.
--
-- @treturn[1] int Child process ID (in the parent process).
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
--
-- @usage
-- local pid, err = sys.spawn(function()
--     print("Hello from child process!")
-- end)
-- if not pid then
--     print("Failed to spawn child:", err)
-- else
--     print("Spawned child PID:", pid)
-- end
function M.spawn(f)
    assert(type(f) == 'function')

    local pid, err = sys.fork()
    if not pid then
        return nil, err
    end

    if pid == 0 then
        eco.init()
        sys.prctl(sys.PR_SET_PDEATHSIG, sys.SIGKILL)
        f()
        os.exit()
    end
end

---
-- Listen for a specific signal and invoke a callback asynchronously.
--
-- This function wraps `signalfd` and spawns a coroutine to continuously
-- read the signal. When the specified signal `sig` is received, the
-- callback `cb` is invoked with any additional arguments.
--
-- @function signal
-- @tparam int sig Signal number to listen for (e.g., @{sys.SIGINT}).
-- @tparam function cb Callback function to invoke when the signal occurs.
-- @tparam ... Additional arguments passed to the callback.
--
-- @treturn eco.reader Reader object for the signal.
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
--
-- @usage
-- local rd, err = sys.signal(sys.SIGINT, function()
--     print('Received SIGINT!')
-- end)
-- if not rd then
--     print('Failed to listen for signal:', err)
-- end
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
