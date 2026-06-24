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

local function with_http_client(fake_socket, fn)
    local names = {
        'eco.http.client',
        'eco.socket',
        'eco.file'
    }
    local saved = {}

    for _, name in ipairs(names) do
        if package.loaded[name] == nil then
            saved[name] = SENTINEL
        else
            saved[name] = package.loaded[name]
        end
    end

    package.loaded['eco.socket'] = fake_socket
    package.loaded['eco.file'] = {}
    package.loaded['eco.http.client'] = nil

    local ok, http_or_err = pcall(require, 'eco.http.client')
    if not ok then
        restore_modules(saved)
        error(http_or_err)
    end

    local run_ok, run_err = pcall(fn, http_or_err)

    restore_modules(saved)

    assert(run_ok, run_err)
end

local function make_socket(reads)
    local sock = {
        reads = reads,
        read_index = 0,
        sent = {}
    }

    function sock:send(data)
        self.sent[#self.sent + 1] = data
        return #data
    end

    function sock:read(mode)
        self.read_index = self.read_index + 1

        local item = self.reads[self.read_index]
        assert(item, 'unexpected read')

        if item[1] == false then
            return nil, item[2]
        end

        return item[1]
    end

    function sock:close()
        self.closed = true
    end

    return sock
end

local function make_socket_module(sock)
    return {
        is_ip_address = function()
            return true
        end,
        connect_tcp = function()
            return sock
        end
    }
end

do
    local sock = make_socket({
        { 'HTTP/1.1 200 OK' },
        { '' },
        { 'hello' },
        { false, 'closed' }
    })

    with_http_client(make_socket_module(sock), function(http)
        local resp, err = http.request('GET', 'http://127.0.0.1/close', nil, {
            timeout = 1.0
        })

        assert(resp, err)
        assert(resp.body == 'hello')
        assert(sock.closed == true)
    end)
end

do
    local sock = make_socket({
        { 'HTTP/1.1 200 OK' },
        { '' },
        { 'partial' },
        { false, 'timeout' }
    })

    with_http_client(make_socket_module(sock), function(http)
        local resp, err = http.request('GET', 'http://127.0.0.1/slow', nil, {
            timeout = 0.1
        })

        assert(resp == nil)
        assert(err == 'read body fail: timeout')
        assert(sock.closed == true)
    end)
end

do
    local sock = make_socket({
        { 'HTTP/1.1 200 OK' },
        { '' },
        { 'partial' },
        { false, 'eof' }
    })

    with_http_client(make_socket_module(sock), function(http)
        local resp, err = http.request('GET', 'http://127.0.0.1/eof', nil, {
            timeout = 1.0
        })

        assert(resp == nil)
        assert(err == 'read body fail: eof')
        assert(sock.closed == true)
    end)
end

print('http close-delimited client tests passed')
