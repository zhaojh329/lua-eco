#!/usr/bin/env eco

local eco = require 'eco'
local sys = require 'eco.sys'
local ifile = require 'eco.internal.file'
local test = require 'test'

local function run_loop_case(name, fn)
    test.run_case_async(name, fn)
end

-- Constants/basic API checks.
assert(math.type(sys.SIGINT) == 'integer')
assert(math.type(sys.SIGTERM) == 'integer')
assert(math.type(sys.SIGHUP) == 'integer')
assert(math.type(sys.SIG_BLOCK) == 'integer')
assert(math.type(sys.SIG_UNBLOCK) == 'integer')
assert(math.type(sys.SIG_SETMASK) == 'integer')
assert(math.type(sys.ENOENT) == 'integer')
assert(math.type(sys.EINVAL) == 'integer')
assert(math.type(sys.PR_SET_PDEATHSIG) == 'integer')

local pid = sys.getpid()
local ppid = sys.getppid()
assert(math.type(pid) == 'integer' and pid > 0)
assert(math.type(ppid) == 'integer' and ppid > 0)

local up = sys.uptime()
assert(math.type(up) == 'integer' and up >= 0)

local nprocs = sys.get_nprocs()
assert(math.type(nprocs) == 'integer' and nprocs >= 1)

local estr = sys.strerror(sys.EINVAL)
assert(type(estr) == 'string' and #estr > 0)

local ok, err = sys.prctl(sys.PR_SET_PDEATHSIG, sys.SIGTERM)
assert(ok == true, err)

ok, err = sys.prctl(0x7fffffff, 0)
assert(ok == nil and err == 'unsupported option')

-- getpwnam success and not-found behavior.
do
    local name = os.getenv('USER') or os.getenv('LOGNAME') or 'root'
    local info

    info, err = sys.getpwnam(name)
    if not info then
        info, err = sys.getpwnam('root')
    end

    assert(info, err)
    assert(type(info.username) == 'string' and #info.username > 0)
    assert(math.type(info.uid) == 'integer')
    assert(math.type(info.gid) == 'integer')
    assert(type(info.home) == 'string')
    assert(type(info.shell) == 'string')

    local miss_name = string.format('__eco_no_user_%d__', pid)
    local miss

    miss, err = sys.getpwnam(miss_name)
    assert(miss == nil and err == 'not found')
end

-- Signal listener semantics.
run_loop_case('signal listen/close', function()
    local got = 0
    local sig, serr = sys.signal(sys.SIGUSR1, function(tag)
        assert(tag == 'sig')
        got = got + 1
    end, 'sig')

    assert(sig, serr)

    local kok, kerr = sys.kill(sys.getpid(), sys.SIGUSR1)
    assert(kok == true, kerr)

    eco.sleep(0.02)

    assert(got == 1, 'signal callback should run exactly once')

    sig:close()
    sig:close()
end)

run_loop_case('signal early close', function()
    local got = 0
    local sig, serr = sys.signal(sys.SIGWINCH, function()
        got = got + 1
    end)

    assert(sig, serr)

    -- Close before any signal delivery; callback must never run afterwards.
    sig:close()
    sig:close()

    local kok, kerr = sys.kill(sys.getpid(), sys.SIGWINCH)
    assert(kok == true, kerr)

    eco.sleep(0.02)

    assert(got == 0, 'signal callback should not run after early close')
end)

run_loop_case('signal reject SIGCHLD', function()
    local ok, err = pcall(sys.signal, sys.SIGCHLD, function() end)

    assert(ok == false)
    assert(type(err) == 'string' and err:find('SIGCHLD', 1, true))
end)

-- Signal GC regression: after close, signal object should be collectible.
do
    local weak = setmetatable({}, { __mode = 'v' })
    local sfd

    run_loop_case('signal close then gc', function()
        local sig, serr = sys.signal(sys.SIGWINCH, function() end)
        assert(sig, serr)

        sfd = sig.sfd
        weak.sig = sig

        sig:close()
    end)

    test.full_gc()

    assert(weak.sig == nil, 'signal object should be collectible after close')

    local c, e = ifile.close(sfd)
    assert(c == nil and type(e) == 'string', 'signal fd should already be closed before GC check')
end

-- spawn API semantics.
run_loop_case('spawn child callback', function()
    local marker = string.format('/tmp/eco-spawn-%d-%d.marker', pid, os.time())
    os.remove(marker)

    local child_pid, serr = sys.spawn(function()
        local f = io.open(marker, 'wb')
        if f then
            f:write('spawn-ok')
            f:close()
        end
    end)

    assert(child_pid, serr)
    assert(math.type(child_pid) == 'integer' and child_pid > 0)

    local done = false

    for _ = 1, 200 do
        local f = io.open(marker, 'rb')
        if f then
            local data = f:read('*a')
            f:close()

            assert(data == 'spawn-ok')
            done = true
            break
        end

        eco.sleep(0.01)
    end

    assert(done, 'spawn child callback should create marker file')

    os.remove(marker)
end)

-- exec/process API semantics.
run_loop_case('exec read/wait/close', function()
    local p, perr = sys.exec('/bin/sh', '-c', 'printf out; printf err 1>&2; exit 7')
    assert(p, perr)

    local stdout, err1 = p:read_stdout('*a', 1)
    assert(stdout == 'out', err1)

    local stderr, err2 = p:read_stderr('*a', 1)
    assert(stderr == 'err', err2)

    local waited_pid, status = p:wait(1)
    assert(waited_pid == p.pid)
    assert(type(status) == 'table' and status.exited == true and status.status == 7)

    local again_pid, werr = p:wait(0.02)
    assert(again_pid == nil and werr == 'timeout', 'second wait should timeout once status is consumed')

    p:close()
    p:close()
end)

run_loop_case('exec signal(sigterm)', function()
    local p, perr = sys.exec('/bin/sh', '-c', 'sleep 5')
    assert(p, perr)

    local sig_ok, terr = p:signal(sys.SIGTERM)
    assert(sig_ok == true, terr)

    local waited_pid, status = p:wait(1)
    assert(waited_pid == p.pid)
    assert(type(status) == 'table' and status.signaled == true)
    assert(status.status == sys.SIGTERM)

    p:close()
end)

run_loop_case('exec kill', function()
    local p, perr = sys.exec('/bin/sh', '-c', 'sleep 5')
    assert(p, perr)

    local kill_ok, kerr = p:kill()
    assert(kill_ok == true, kerr)

    local waited_pid, status = p:wait(1)
    assert(waited_pid == p.pid)
    assert(type(status) == 'table' and status.signaled == true)
    assert(status.status == sys.SIGKILL)

    p:close()
end)

run_loop_case('exec stop', function()
    local p, perr = sys.exec('/bin/sh', '-c', 'sleep 5')
    assert(p, perr)

    local waited_pid, status = p:stop(0.2)

    assert(waited_pid == p.pid)
    assert(type(status) == 'table' and status.signaled == true)
    assert(status.status == sys.SIGTERM or status.status == sys.SIGKILL)

    p:close()
end)

run_loop_case('exec table env form', function()
    local p, perr = sys.exec({ '/bin/sh', '-c', 'printf %s "$A"' }, { 'A=eco' })
    assert(p, perr)

    local stdout, err1 = p:read_stdout('*a', 1)
    assert(stdout == 'eco', err1)

    local stderr, err2 = p:read_stderr('*a', 1)
    assert(stderr == nil and err2 == 'eof')

    local _, status = p:wait(1)
    assert(status and status.exited and status.status == 0)

    p:close()
end)

run_loop_case('sh wrapper', function()
    local stdout, stderr, sherr = sys.sh('printf S; printf E 1>&2', 1)
    assert(stdout == 'S')
    assert(stderr == 'E')
    assert(sherr == nil)

    stdout, stderr, sherr = sys.sh('sleep 0.1', 0.01)
    assert(stdout == nil and stderr == nil and sherr == 'timeout')
end)

-- Stress + leak regression for repeated exec/wait/close bursts.
run_loop_case('exec burst memory plateau', function()
    local function exec_burst(rounds, n)
        local total = 0

        for _ = 1, rounds do
            local procs = {}

            for _ = 1, n do
                local p, err = sys.exec('/bin/sh', '-c', 'exit 0')
                assert(p, err)
                procs[#procs + 1] = p
            end

            for i = 1, #procs do
                local p = procs[i]
                local _, status = p:wait(2)
                assert(status and status.exited and status.status == 0)
                p:close()
            end

            total = total + #procs
        end

        return total
    end

    local rounds = 4
    local n = 40
    local expected = rounds * n

    local base_mem_kb = test.lua_mem_kb()

    assert(exec_burst(rounds, n) == expected)
    local after_first_kb = test.lua_mem_kb()

    assert(exec_burst(rounds, n) == expected)
    local after_second_kb = test.lua_mem_kb()

    local growth_first_kb = after_first_kb - base_mem_kb
    local growth_second_kb = after_second_kb - after_first_kb
    local plateau_limit_kb = math.max(128, growth_first_kb * 0.35)

    assert(growth_first_kb < 8192,
           string.format('unexpectedly large initial sys memory growth: %.2f KB', growth_first_kb))

    assert(growth_second_kb <= plateau_limit_kb,
           string.format('sys memory keeps growing across equal bursts: first %.2f KB, second %.2f KB (limit %.2f KB)',
                         growth_first_kb, growth_second_kb, plateau_limit_kb))
end)

-- Automatic GC regression for process handles (__gc should close captured fds).
do
    local weak = setmetatable({}, { __mode = 'v' })
    local outfd, errfd

    run_loop_case('process auto gc close fds', function()
        local p, perr = sys.exec('/bin/sh', '-c', 'printf x; printf y 1>&2; exit 0')
        assert(p, perr)

        outfd = p.stdout_fd
        errfd = p.stderr_fd
        weak.p = p

        local stdout, err1 = p:read_stdout('*a', 1)
        assert(stdout == 'x', err1)

        local stderr, err2 = p:read_stderr('*a', 1)
        assert(stderr == 'y', err2)

        local _, status = p:wait(1)
        assert(status and status.exited and status.status == 0)
    end)

    test.full_gc()

    assert(weak.p == nil, 'process handle should be collectible when unreachable')

    local c1, e1 = ifile.close(outfd)
    assert(c1 == nil and type(e1) == 'string', 'stdout fd should be auto-closed by __gc')

    local c2, e2 = ifile.close(errfd)
    assert(c2 == nil and type(e2) == 'string', 'stderr fd should be auto-closed by __gc')
end

print('sys tests passed')
