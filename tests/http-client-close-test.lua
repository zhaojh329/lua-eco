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

    local ok, http_or_err = pcall(dofile, 'http/client.lua')
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

    function sock:readfull(mode)
        return self:read(mode)
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

do
    local sock = make_socket({
        { 'HTTP/1.1 200 OK' },
        { 'Content-Length: 11' },
        { '' },
        { 'hello' },
        { ' world' }
    })

    with_http_client(make_socket_module(sock), function(http)
        local chunks = {}
        local resp, err = http.request('GET', 'http://127.0.0.1/fixed', nil, {
            timeout = 1.0,
            body_to_file = function(data)
                chunks[#chunks + 1] = data
            end
        })

        assert(resp, err)
        assert(resp.body == nil)
        assert(table.concat(chunks) == 'hello world')
        assert(sock.closed == true)
    end)
end

do
    local sock = make_socket({
        { 'HTTP/1.1 200 OK' },
        { 'Transfer-Encoding: chunked' },
        { '' },
        { '5' },
        { 'hello' },
        { '' },
        { '6' },
        { ' world' },
        { '' },
        { '0' },
        { '' }
    })

    with_http_client(make_socket_module(sock), function(http)
        local chunks = {}
        local resp, err = http.request('GET', 'http://127.0.0.1/chunked', nil, {
            timeout = 1.0,
            body_to_file = function(data)
                chunks[#chunks + 1] = data
            end
        })

        assert(resp, err)
        assert(resp.body == nil)
        assert(#chunks == 2)
        assert(table.concat(chunks) == 'hello world')
        assert(sock.closed == true)
    end)
end

do
    local sock = make_socket({
        { 'HTTP/1.1 200 OK' },
        { '' },
        { 'hello' },
        { ' world' },
        { false, 'closed' }
    })

    with_http_client(make_socket_module(sock), function(http)
        local chunks = {}
        local resp, err = http.request('GET', 'http://127.0.0.1/close-callback', nil, {
            timeout = 1.0,
            body_to_file = function(data)
                chunks[#chunks + 1] = data
            end
        })

        assert(resp, err)
        assert(resp.body == nil)
        assert(table.concat(chunks) == 'hello world')
        assert(sock.closed == true)
    end)
end

print('http close-delimited/body_to_file client tests passed')
