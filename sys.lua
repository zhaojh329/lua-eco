-- SPDX-License-Identifier: MIT
-- Author: Jianhui Zhao <zhaojh329@gmail.com>

--- System and process related utilities.
-- @module eco.sys

local file = require 'eco.internal.file'
local sys = require 'eco.internal.sys'
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

local procs = setmetatable({}, { __mode = 'v' })
local sigchld

local function sigchld_dispatch(pid, status)
    local p = procs[pid]
    if not p then
        return
    end

    local wait_cond = p.wait_cond
    if wait_cond then
        local ok = wait_cond:signal({ pid = pid, status = status })
        if not ok then
            p.__status = status
        end
    else
        p.__status = status
    end
end

local function ensure_sigchld()
    if sigchld then
        return true
    end

    eco._set_sigchld_hook(sigchld_dispatch)

    sigchld = true
    return true
end

--- Process handle returned by @{sys.exec}.
--
-- This object represents a running child process.
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

--- Wait for the process to exit.
--
-- If the child has already exited before calling this method,
-- it returns immediately with the status cached on this process handle.
--
-- @function process:wait
-- @tparam[opt] number timeout Timeout in seconds.
-- @treturn int pid Process id.
-- @treturn int status Exit status.
-- @treturn[2] nil On timeout or error.
-- @treturn[2] string Error message.
function exec_methods:wait(timeout)
    local status = self.__status
    if status then
        self.__status = nil
        return self.pid, status
    end

    local c = sync.cond()

    self.wait_cond = c

    status = self.__status
    if status then
        self.__status = nil
        self.wait_cond = nil
        return self.pid, status
    end

    local res, err = c:wait(timeout)

    self.wait_cond = nil

    if not res then
        return nil, err
    end

    return res.pid, res.status
end

--- Send a signal to the process.
--
-- @function process:signal
-- @tparam int sig Signal number.
-- @treturn boolean true On success.
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
function exec_methods:signal(sig)
    return sys.kill(self.pid, sig)
end

--- Force kill the process with SIGKILL.
--
-- @function process:kill
-- @treturn boolean true On success.
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
function exec_methods:kill()
    return self:signal(sys.SIGKILL)
end

--- Stop the process gracefully, then force kill if needed.
--
-- This sends SIGTERM first, waits up to `timeout` seconds, then sends
-- SIGKILL if the process is still alive. Waiting remains coroutine-based.
--
-- @function process:stop
-- @tparam[opt=3] number timeout Wait timeout in seconds for each phase.
-- @treturn int pid Process id.
-- @treturn table status Exit status table.
-- @treturn[2] nil On error.
-- @treturn[2] string Error message.
function exec_methods:stop(timeout)
    timeout = timeout or 3

    local ok, err = self:signal(sys.SIGTERM)

    if not ok then
        return nil, err
    end

    local pid, status = self:wait(timeout)
    if pid then
        return pid, status
    end

    if status ~= 'timeout' then
        return nil, status
    end

    ok, err = self:kill()
    if not ok then
        return nil, err
    end

    return self:wait(timeout)
end

--- Read from process stdout.
--
-- See @{eco.reader:read}
--
-- @function process:read_stdout
function exec_methods:read_stdout(pattern, timeout)
    return self.stdout_rd:read(pattern, timeout)
end

--- Read from process stderr.
--
-- See @{eco.reader:read}
--
-- @function process:read_stderr
function exec_methods:read_stderr(pattern, timeout)
    return self.stderr_rd:read(pattern, timeout)
end

--- End of `process` class section.
-- @section end

local exec_metatable = {
    __index = exec_methods,
    __gc = exec_methods.close,
    __close = exec_methods.close
}

--- Execute a program.
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
    ensure_sigchld()

    local pid, stdout_fd, stderr_fd = sys.exec(...)
    if not pid then
        return nil, stdout_fd
    end

    local p = setmetatable({
        pid = pid,
        stdout_fd = stdout_fd,
        stderr_fd = stderr_fd,
        stdout_rd = eco.reader(stdout_fd),
        stderr_rd = eco.reader(stderr_fd)
    }, exec_metatable)

    procs[pid] = p

    return p
end

--- Execute a shell command and return stdout and stderr.
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

--- Spawn a new process to run a Lua function.
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
        eco._init()
        -- Ensure child is killed automatically if parent process exits.
        sys.prctl(sys.PR_SET_PDEATHSIG, sys.SIGKILL)
        eco.run(f)
        eco.loop()
        os.exit()
    end

    return pid
end

--- Signal handle returned by @{sys.signal}.
--
-- This object represents one signal listener created by @{sys.signal}.
--
-- Call @{signal:close} to stop listening and release underlying resources.
-- The close operation is idempotent.
--
-- @type signal

local signal_methods = {}

---
-- Stop listening for the signal and release resources.
--
-- This closes the internal `signalfd`, cancels pending read operations,
-- and restores the process signal mask for this signal.
-- Calling this method multiple times is safe.
--
-- @function signal:close
function signal_methods:close()
    if not self.sfd then
        return
    end

    self.rd:cancel()

    file.close(self.sfd)
    sys.sigprocmask(sys.SIG_UNBLOCK, self.signum)

    self.sfd = nil
end

--- End of `signal` class section.
-- @section end

local signal_mt = {
    __index = signal_methods,
    __gc = signal_methods.close,
    __close = signal_methods.close
}

--- Listen for a specific signal and invoke a callback asynchronously.
--
-- This function wraps `signalfd` and spawns a coroutine to continuously
-- read the signal. When the specified signal `sig` is received, the
-- callback `cb` is invoked with any additional arguments.
--
-- The returned @{signal} object controls the listener lifetime.
-- Call `sig:close()` to stop listening.
--
-- Internally this function blocks `signum` in the process mask and uses
-- `signalfd` for delivery. The signal will be unblocked when the listener
-- is closed.
--
-- Note: `SIGCHLD` is reserved by eco's scheduler for child process reaping
-- and must not be listened to via this API.
--
-- @function signal
-- @tparam int signum Signal number to listen for (e.g., @{sys.SIGINT}).
-- @tparam function cb Callback function to invoke when the signal occurs.
-- @tparam ... Additional arguments passed to the callback.
-- @treturn signal Signal object (use @{signal:close} to stop listening).
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
--
-- @usage
-- local sig
-- sig, err = sys.signal(sys.SIGINT, function()
--     print('Received SIGINT!')
--     sig:close()
-- end)
-- if not sig then
--     print('Failed to listen for signal:', err)
-- end
function M.signal(signum, cb, ...)
    assert(signum ~= sys.SIGCHLD, 'SIGCHLD is reserved by eco scheduler')

    local ok, err = sys.sigprocmask(sys.SIG_BLOCK, signum)
    if not ok then
        return nil, err
    end

    local sfd, err = sys.signalfd(signum)
    if not sfd then
        sys.sigprocmask(sys.SIG_UNBLOCK, signum)
        return nil, err
    end

    local obj = {
        sfd = sfd,
        signum = signum,
        rd = eco.reader(sfd)
    }

    eco.run(function(...)
        while true do
            local si = obj.rd:read(128)
            if not si then
                return
            end

            local sig = string.unpack('I4', si)
            if sig == signum then
                cb(...)
            end
        end
    end, ...)

    return setmetatable(obj, signal_mt)
end

return setmetatable(M, { __index = sys })
