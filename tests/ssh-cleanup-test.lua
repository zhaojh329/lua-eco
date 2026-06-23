#!/usr/bin/env eco

local SENTINEL = {}
local SSH_PATH = 'ssh.lua'

do
    local f = io.open(SSH_PATH)
    if f then
        f:close()
    else
        SSH_PATH = '../ssh.lua'
    end
end

local function restore_modules(saved)
    for name, value in pairs(saved) do
        if value == SENTINEL then
            package.loaded[name] = nil
        else
            package.loaded[name] = value
        end
    end
end

local function with_ssh_env(env, fn)
    local names = {
        'eco.ssh',
        'eco.internal.ssh',
        'eco.socket',
        'eco.file',
        'eco.time',
        'eco.sys',
        'eco'
    }
    local saved = {}

    for _, name in ipairs(names) do
        if package.loaded[name] == nil then
            saved[name] = SENTINEL
        else
            saved[name] = package.loaded[name]
        end
    end

    package.loaded['eco.internal.ssh'] = env.ssh
    package.loaded['eco.socket'] = env.socket
    package.loaded['eco.file'] = {}
    package.loaded['eco.time'] = { sleep = function() end }
    package.loaded['eco.sys'] = { uptime = function() return 0 end }
    package.loaded['eco'] = env.eco
    package.loaded['eco.ssh'] = nil

    local ok, ssh_or_err = pcall(dofile, SSH_PATH)
    if not ok then
        restore_modules(saved)
        error(ssh_or_err)
    end

    local run_ok, run_err = pcall(fn, ssh_or_err)

    restore_modules(saved)

    assert(run_ok, run_err)
end

local function make_env(session)
    local sock = {
        close_count = 0
    }

    function sock:getfd()
        return 7
    end

    function sock:close()
        self.close_count = self.close_count + 1
    end

    local io = {
        wait_count = 0,
        wait_ok = true
    }

    function io:wait()
        self.wait_count = self.wait_count + 1
        return self.wait_ok
    end

    local ssh_mod = {
        ERROR_EAGAIN = -37,
        SESSION_BLOCK_INBOUND = 1,
        SESSION_BLOCK_OUTBOUND = 2,
        DISCONNECT_BY_APPLICATION = 11
    }

    function ssh_mod.new()
        return session
    end

    return {
        session = session,
        sock = sock,
        io = io,
        ssh = ssh_mod,
        socket = {
            is_ipv4_address = function()
                return true
            end,
            is_ipv6_address = function()
                return false
            end,
            connect_tcp = function()
                return sock
            end
        },
        eco = {
            READ = 1,
            WRITE = 2,
            io = function()
                return io
            end
        }
    }
end

local function base_session()
    local session = {
        free_count = 0,
        disconnect_count = 0
    }

    function session:block_directions()
        return 1
    end

    function session:last_error()
        return self.last_error_value or 'session error'
    end

    function session:last_errno()
        return self.last_errno_value or -1
    end

    function session:disconnect()
        self.disconnect_count = self.disconnect_count + 1
        return true
    end

    function session:free()
        self.free_count = self.free_count + 1
        return true
    end

    return session
end

local function assert_cleanup(env, expected_err)
    assert(env.session.free_count == 1, 'session should be freed once')
    assert(env.session.disconnect_count == 0, 'failed setup should not disconnect')
    assert(env.sock.close_count == 1, 'socket should be closed once')
    assert(expected_err, 'missing expected error')
end

do
    local session = base_session()
    session.last_error_value = 'handshake failed'

    function session:handshake()
        return nil, -5
    end

    local env = make_env(session)

    with_ssh_env(env, function(ssh)
        local conn, err = ssh.new('127.0.0.1', 22, 'root', 'pw')
        assert(conn == nil)
        assert(err == 'handshake failed', tostring(err))
    end)

    assert_cleanup(env, true)
end

do
    local session = base_session()

    function session:handshake()
        return nil, -37
    end

    local env = make_env(session)
    env.io.wait_ok = false

    with_ssh_env(env, function(ssh)
        local conn, err = ssh.new('127.0.0.1', 22, 'root', 'pw')
        assert(conn == nil)
        assert(err == 'handshake timeout', tostring(err))
    end)

    assert_cleanup(env, true)
end

do
    local session = base_session()
    session.last_errno_value = -99

    function session:handshake()
        return true
    end

    function session:userauth_list()
        return nil, 'userauth list failed'
    end

    local env = make_env(session)

    with_ssh_env(env, function(ssh)
        local conn, err = ssh.new('127.0.0.1', 22, 'root', 'pw')
        assert(conn == nil)
        assert(err == 'userauth list failed', tostring(err))
    end)

    assert_cleanup(env, true)
end

do
    local session = base_session()
    session.last_error_value = 'authentication failed'

    function session:handshake()
        return true
    end

    function session:userauth_list()
        return 'password'
    end

    function session:userauth_password()
        return nil, -18
    end

    local env = make_env(session)

    with_ssh_env(env, function(ssh)
        local conn, err = ssh.new('127.0.0.1', 22, 'root', 'pw')
        assert(conn == nil)
        assert(err == 'authentication failed', tostring(err))
    end)

    assert_cleanup(env, true)
end

do
    local session = base_session()

    function session:handshake()
        return true
    end

    function session:userauth_list()
        return ''
    end

    local env = make_env(session)

    with_ssh_env(env, function(ssh)
        local conn, err = ssh.new('127.0.0.1', 22, 'root', 'pw')
        assert(conn, err)
    end)

    assert(session.free_count == 0)
    assert(env.sock.close_count == 0)
end

print('ssh cleanup tests passed')
