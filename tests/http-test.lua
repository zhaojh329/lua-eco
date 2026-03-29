#!/usr/bin/env eco

local http_client = require 'eco.http.client'
local http_url = require 'eco.http.url'
local sys = require 'eco.sys'
local socket = require 'eco.socket'
local file = require 'eco.file'
local time = require 'eco.time'
local eco = require 'eco'

local function run_eco(fn)
    local ok, err = pcall(fn)
    assert(ok, err)
end

local function request(method, url, body, opts)
    local resp, err

    run_eco(function()
        resp, err = http_client.request(method, url, body, opts)
    end)

    return resp, err
end

local function send_raw_http(port, payload, timeout)
    local data

    run_eco(function()
        local s, err = socket.connect_tcp('127.0.0.1', port, {
            timeout = timeout or 1.0
        })
        assert(s, err)

        local ok, serr = s:send(payload)
        assert(ok, serr)

        data = s:read(4096, timeout or 1.0)
        s:close()
    end)

    return data
end

local function start_server(port, docroot)
    local pid, err = sys.spawn(function()
        local http = require 'eco.http.server'

        local function handler(con, req)
            if req.path == '/ready' then
                con:add_header('content-length', '2')
                con:send('ok')
                return
            end

            if req.path == '/query' then
                local v = req.query.a or ''
                con:add_header('x-query-a', v)
                con:send(v)
                return
            end

            if req.path == '/echo' then
                local body, rerr = con:read_body(nil, 2.0)
                if not body then
                    return con:send_error(http.STATUS_BAD_REQUEST, nil, rerr)
                end

                con:add_header('x-echo-len', tostring(#body))
                con:send(body)
                return
            end

            if req.path == '/chunked' then
                con:add_header('content-type', 'text/plain')
                con:send('chunk-')
                con:send('body')
                return
            end

            if req.path == '/upload-form' then
                local parts = {}
                local current_name

                while true do
                    local typ, data = con:read_formdata(req, 2.0)
                    if not typ then
                        return con:send_error(http.STATUS_BAD_REQUEST, nil, data)
                    end

                    if typ == 'header' then
                        if data[1] == 'content-disposition' then
                            current_name = data[2]:match('name="([^"]+)"')
                        end
                    elseif typ == 'body' then
                        if current_name then
                            parts[current_name] = (parts[current_name] or '') .. data[1]

                            if data[2] then
                                current_name = nil
                            end
                        end
                    elseif typ == 'end' then
                        break
                    end
                end

                con:add_header('content-type', 'text/plain')
                con:send((parts.name or '') .. '|' .. (parts.note or '') .. '|' .. tostring(#(parts.file or '')))
                return
            end

            if req.path == '/missing' then
                return con:send_error(http.STATUS_NOT_FOUND, nil, 'missing')
            end

            if req.path == '/redirect' then
                return con:redirect(http.STATUS_FOUND, '/index.html')
            end

            return con:serve_file(req)
        end

        local options = {
            reuseaddr = true,
            docroot = docroot,
            index = 'index.html',
            gzip = false,
            http_keepalive = 2
        }

        local _, serr = http.listen('127.0.0.1', port, options, handler)
        assert(serr == nil, serr)
    end)

    assert(pid, err)
    return pid
end

local function wait_server_ready(base_url)
    for _ = 1, 120 do
        local resp = request('GET', base_url .. '/ready', nil, { timeout = 0.1 })
        if resp and resp.code == 200 then
            return true
        end

        run_eco(function()
            time.sleep(0.01)
        end)
    end

    return nil, 'server not ready in time'
end

local tmp_root
local ok, err = xpcall(function()
    local probe = assert(socket.listen_tcp('127.0.0.1', 0, { reuseaddr = true }))
    local addr = assert(probe:getsockname())
    local port = addr.port
    probe:close()

    tmp_root = string.format('/tmp/eco-http-test-%d-%d', sys.getpid(), math.floor(time.now() * 1000))
    assert(os.execute('mkdir -p ' .. tmp_root) == true)

    local index_path = tmp_root .. '/index.html'
    do
        local f = assert(io.open(index_path, 'wb'))
        f:write('hello-http-index')
        f:close()
    end

    local upload_path = tmp_root .. '/upload.bin'
    do
        local f = assert(io.open(upload_path, 'wb'))
        f:write('ABCDE')
        f:close()
    end

    local outside_name = string.format('eco-http-outside-%d.txt', sys.getpid())
    local outside_path = '/tmp/' .. outside_name
    do
        local f = assert(io.open(outside_path, 'wb'))
        f:write('outside-data')
        f:close()
    end

    start_server(port, tmp_root)

    local base = 'http://127.0.0.1:' .. tostring(port)
    assert(wait_server_ready(base))

    local resp, rerr

    -- client + server: query parsing and plain body.
    resp, rerr = request('GET', base .. '/query?a=hello%20eco', nil, { timeout = 1.0 })
    assert(resp and resp.code == 200, rerr)
    assert(resp.body == 'hello eco')
    assert(resp.headers['x-query-a'] == 'hello eco')

    -- client + server: chunked body receive path.
    resp, rerr = request('GET', base .. '/chunked', nil, { timeout = 1.0 })
    assert(resp and resp.code == 200, rerr)
    assert(resp.body == 'chunk-body')
    assert(resp.headers['transfer-encoding'] == 'chunked')

    -- client + server: POST text body read/echo.
    resp, rerr = request('POST', base .. '/echo', 'payload', { timeout = 1.0 })
    assert(resp and resp.code == 200, rerr)
    assert(resp.body == 'payload')
    assert(resp.headers['x-echo-len'] == '7')

    -- client body_with_file path.
    local body_file, ferr = http_client.body_with_file(upload_path)
    assert(body_file, ferr)

    resp, rerr = request('POST', base .. '/echo', body_file, { timeout = 1.0 })
    assert(resp and resp.code == 200, rerr)
    assert(resp.body == 'ABCDE')
    assert(resp.headers['x-echo-len'] == '5')

    -- client form() + server read_formdata() path.
    local form = http_client.form()
    form:add('name', 'eco')
    form:add('note', 'ok')

    local fok, fe = form:add_file('file', upload_path)
    assert(fok, fe)

    resp, rerr = request('POST', base .. '/upload-form', form, { timeout = 2.0 })
    assert(resp and resp.code == 200, rerr)
    assert(resp.body == 'eco|ok|5')

    -- server serve_file GET + client HEAD semantics.
    resp, rerr = request('GET', base .. '/index.html', nil, { timeout = 1.0 })
    assert(resp and resp.code == 200, rerr)
    assert(resp.body == 'hello-http-index')
    assert(resp.headers['content-length'] == tostring(#'hello-http-index'))

    local etag = resp.headers['etag']

    -- server 304 should not be chunked and should have no body bytes.
    resp, rerr = request('GET', base .. '/index.html', nil, {
        timeout = 1.0,
        headers = {
            ['If-None-Match'] = etag
        }
    })
    assert(resp and resp.code == 304, rerr)
    assert(resp.headers['transfer-encoding'] == nil)
    assert(resp.headers['content-length'] == '0')
    assert(resp.body == '')

    resp, rerr = request('HEAD', base .. '/index.html', nil, { timeout = 1.0 })
    assert(resp and resp.code == 200, rerr)
    assert(resp.body == nil)
    assert(resp.headers['content-length'] == tostring(#'hello-http-index'))

    -- client body_to_file path.
    local downloaded = tmp_root .. '/download.out'
    resp, rerr = request('GET', base .. '/chunked', nil, {
        timeout = 1.0,
        body_to_file = downloaded
    })
    assert(resp and resp.code == 200, rerr)
    assert(resp.body == nil)

    do
        local f = assert(io.open(downloaded, 'rb'))
        local data = assert(f:read('*a'))
        f:close()
        assert(data == 'chunk-body')
    end

    -- error/redirect paths.
    resp, rerr = request('GET', base .. '/missing', nil, { timeout = 1.0 })
    assert(resp and resp.code == 404, rerr)
    assert(resp.body == 'missing')

    resp, rerr = request('GET', base .. '/redirect', nil, { timeout = 1.0 })
    assert(resp and resp.code == 302, rerr)
    assert(resp.headers['location'] == '/index.html')

    -- static file path traversal should not escape docroot.
    resp, rerr = request('GET', base .. '/..%2F' .. outside_name, nil, { timeout = 1.0 })
    assert(resp and resp.code == 403, rerr)
    assert(resp.body == '')

    -- malformed content-length should not crash request handling loop.
    send_raw_http(port, table.concat({
        'GET /ready HTTP/1.1\r\n',
        'Host: 127.0.0.1\r\n',
        'Content-Length: abc\r\n',
        'Connection: close\r\n',
        '\r\n'
    }))

    resp, rerr = request('GET', base .. '/ready', nil, { timeout = 1.0 })
    assert(resp and resp.code == 200, rerr)
    assert(resp.body == 'ok')

    -- URL parser supports bracketed IPv6 literal hosts.
    local parsed, perr = http_url.parse('http://[::1]:8080/v6?q=1')
    assert(parsed, perr)
    assert(parsed.host == '::1')
    assert(parsed.port == 8080)
    assert(parsed.path == '/v6')
    assert(parsed.raw_path == '/v6?q=1')

    -- client-side invalid arguments / unsupported scheme.
    local none, e = http_client.request('GET', 'ftp://127.0.0.1/test', nil, { timeout = 0.2 })
    assert(none == nil and e == 'unsupported scheme: ftp')

    none, e = http_client.request('POST', base .. '/echo', {}, { timeout = 0.2 })
    assert(none == nil and e == 'invalid body')

    -- stress: concurrent client requests against the same server.
    run_eco(function()
        local workers = 8
        local loops = 60
        local finished = 0
        local ok_posts = 0

        for w = 1, workers do
            eco.run(function()
                for i = 1, loops do
                    local payload = string.format('worker-%d-loop-%d', w, i)

                    local r1, e1 = http_client.request('POST', base .. '/echo', payload, {
                        timeout = 2.0
                    })

                    assert(r1 and r1.code == 200, e1)
                    assert(r1.body == payload)

                    ok_posts = ok_posts + 1

                    if i % 10 == 0 then
                        local r2, e2 = http_client.request('GET', base .. '/chunked', nil, {
                            timeout = 2.0
                        })
                        assert(r2 and r2.code == 200, e2)
                        assert(r2.body == 'chunk-body')
                    end
                end

                finished = finished + 1
            end)
        end

        local deadline = time.now() + 30.0

        while finished < workers and time.now() < deadline do
            time.sleep(0.02)
        end

        assert(finished == workers,
               string.format('http stress timeout: finished %d/%d workers', finished, workers))

        assert(ok_posts == workers * loops,
               string.format('http stress request mismatch: %d/%d', ok_posts, workers * loops))
    end)

    os.remove(upload_path)
    os.remove(outside_path)
end, debug.traceback)

if tmp_root and file.access(tmp_root) then
    os.execute('rm -rf ' .. tmp_root)
end

assert(ok, err)

print('http tests passed')
