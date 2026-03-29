#!/usr/bin/env eco

local websocket = require 'eco.websocket'
local http_client = require 'eco.http.client'
local sys = require 'eco.sys'
local socket = require 'eco.socket'
local time = require 'eco.time'
local test = require 'test'

local function request(method, url, body, opts)
    return http_client.request(method, url, body, opts)
end

local function start_server(port)
    local pid, err = sys.spawn(function()
        local websocket_srv = require 'eco.websocket'
        local http = require 'eco.http.server'
        local eco = require 'eco'

        local function handler(con, req)
            if req.path == '/ready' then
                con:add_header('content-length', '2')
                con:send('ok')
                return
            end

            if req.path ~= '/ws' then
                con:send_error(http.STATUS_NOT_FOUND, nil, 'missing')
                return
            end

            local ws, uerr = websocket_srv.upgrade(con, req, {
                max_payload_len = 65535
            })

            if not ws then
                con:send_error(http.STATUS_BAD_REQUEST, nil, uerr)
                return
            end

            while true do
                local data, typ, extra = ws:recv_frame(2.0)
                if not data then
                    return
                end

                if typ == 'text' then
                    local ok_send, se = ws:send_text('echo:' .. data)
                    if not ok_send then
                        return
                    end
                elseif typ == 'binary' then
                    local ok_send, se = ws:send_binary(data .. '-srv')
                    if not ok_send then
                        return
                    end
                elseif typ == 'ping' then
                    local ok_send, se = ws:send_pong(data)
                    if not ok_send then
                        return
                    end
                elseif typ == 'close' then
                    ws:send_close(1000, 'bye')
                    return
                elseif typ == 'pong' then
                    -- ignore pong frames in this test server
                elseif typ == 'continuation' and extra == 'again' then
                    -- ignore fragmented continuation frames in this integration case
                end
            end
        end

        local _, serr = http.listen('127.0.0.1', port, {
            reuseaddr = true,
            http_keepalive = 2
        }, handler)

        assert(serr == nil, serr)
    end)

    assert(pid, err)
    return pid
end

local function wait_server_ready(base_url)
    for _ = 1, 150 do
        local resp = request('GET', base_url .. '/ready', nil, { timeout = 0.1 })
        if resp and resp.code == 200 and resp.body == 'ok' then
            return true
        end

        time.sleep(0.01)
    end

    return nil, 'server not ready in time'
end

test.run_case_async('websocket server and client communicate', function()
    local ok, err = xpcall(function()
        local probe = assert(socket.listen_tcp('127.0.0.1', 0, { reuseaddr = true }))
        local addr = assert(probe:getsockname())
        local port = addr.port
        probe:close()

        start_server(port)

        local base = 'http://127.0.0.1:' .. tostring(port)
        local ws_url = 'ws://127.0.0.1:' .. tostring(port) .. '/ws'

        assert(wait_server_ready(base))

        local ws, cerr = websocket.connect(ws_url, {
            origin = base,
            protocols = { 'chat', 'echo' },
            max_payload_len = 65535
        })
        assert(ws, cerr)

        local n, se = ws:send_text('hello')
        assert(n and se == nil, se)

        local data, typ, extra = ws:recv_frame(2.0)
        assert(data == 'echo:hello' and typ == 'text' and extra == nil,
               string.format('unexpected text frame: data=%s typ=%s extra=%s', tostring(data), tostring(typ), tostring(extra)))

        n, se = ws:send_binary('bin')
        assert(n and se == nil, se)

        data, typ, extra = ws:recv_frame(2.0)
        assert(data == 'bin-srv' and typ == 'binary' and extra == nil,
               string.format('unexpected binary frame: data=%s typ=%s extra=%s', tostring(data), tostring(typ), tostring(extra)))

        n, se = ws:send_ping('probe')
        assert(n and se == nil, se)

        data, typ, extra = ws:recv_frame(2.0)
        assert(data == 'probe' and typ == 'pong' and extra == nil,
               string.format('unexpected pong frame: data=%s typ=%s extra=%s', tostring(data), tostring(typ), tostring(extra)))

        n, se = ws:send_close(1000, 'done')
        assert(n and se == nil, se)

        data, typ, extra = ws:recv_frame(2.0)
        assert(data == 'bye' and typ == 'close' and extra == 1000,
               string.format('unexpected close frame: data=%s typ=%s extra=%s', tostring(data), tostring(typ), tostring(extra)))
    end, debug.traceback)

    assert(ok, err)
end)

print('websocket tests passed')
