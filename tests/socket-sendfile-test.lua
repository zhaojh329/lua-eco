#!/usr/bin/env eco

local SENTINEL = {}

local function restore_modules(saved)
    for name, value in pairs(saved) do
        if value == SENTINEL then
            package.loaded[name] = nil
        else
            package.loaded[name] = value
        end
    end
end

local function with_socket_env(stat_sizes, fn)
    local names = {
        'eco.socket',
        'eco.internal.socket',
        'eco.internal.file',
        'eco.sync',
        'eco'
    }
    local saved = {}
    local writer = {
        calls = {}
    }

    for _, name in ipairs(names) do
        if package.loaded[name] == nil then
            saved[name] = SENTINEL
        else
            saved[name] = package.loaded[name]
        end
    end

    local raw_sock = {
        setoption_calls = {}
    }

    function raw_sock:getfd()
        return 7
    end

    function raw_sock:setoption(name, value)
        self.setoption_calls[#self.setoption_calls + 1] = { name = name, value = value }
        return true
    end

    function writer:sendfile(path, offset, len)
        self.calls[#self.calls + 1] = { path = path, offset = offset, len = len }
        return len
    end

    package.loaded['eco.internal.socket'] = {
        AF_INET = 2,
        AF_INET6 = 10,
        AF_UNIX = 1,
        AF_PACKET = 17,
        AF_NETLINK = 16,
        SOCK_DGRAM = 2,
        SOCK_STREAM = 1,
        SOCK_RAW = 3,
        IPPROTO_ICMP = 1,
        IPPROTO_ICMPV6 = 58,
        IPPROTO_TCP = 6,
        IPPROTO_UDP = 17,
        socket = function()
            return raw_sock
        end,
        socketpair = function()
            return raw_sock, raw_sock
        end,
        is_ipv4_address = function()
            return true
        end,
        is_ipv6_address = function()
            return false
        end
    }

    package.loaded['eco.internal.file'] = {
        stat = function(path)
            local size = stat_sizes[path]
            if not size then
                return nil, 'stat failed'
            end

            return { size = size }
        end
    }

    package.loaded['eco.sync'] = {
        mutex = function()
            return {
                lock = function() end,
                unlock = function() end
            }
        end
    }

    package.loaded['eco'] = {
        reader = function()
            return {}
        end,
        writer = function()
            return writer
        end,
        io = function()
            return {}
        end
    }

    package.loaded['eco.socket'] = nil

    local ok, socket_or_err = pcall(require, 'eco.socket')
    if not ok then
        restore_modules(saved)
        error(socket_or_err)
    end

    local run_ok, run_err = pcall(fn, socket_or_err, writer)

    restore_modules(saved)

    assert(run_ok, run_err)
end

with_socket_env({
    whole = 5,
    tail = 11,
    empty = 0
}, function(socket, writer)
    local sock = assert(socket.tcp())

    local n, err = sock:sendfile('whole')
    assert(n == 5, err)
    assert(writer.calls[1].path == 'whole')
    assert(writer.calls[1].offset == 0)
    assert(writer.calls[1].len == 5)

    n, err = sock:sendfile('tail', nil, 7)
    assert(n == 4, err)
    assert(writer.calls[2].path == 'tail')
    assert(writer.calls[2].offset == 7)
    assert(writer.calls[2].len == 4)

    n, err = sock:sendfile('tail', 3, 2)
    assert(n == 3, err)
    assert(writer.calls[3].path == 'tail')
    assert(writer.calls[3].offset == 2)
    assert(writer.calls[3].len == 3)

    n, err = sock:sendfile('empty')
    assert(n == 0, err)
    assert(#writer.calls == 3)

    n, err = sock:sendfile('tail', nil, 20)
    assert(n == 0, err)
    assert(#writer.calls == 3)

    n, err = sock:sendfile('missing')
    assert(n == nil)
    assert(err == 'stat failed', tostring(err))
    assert(#writer.calls == 3)
end)

print('socket sendfile tests passed')
