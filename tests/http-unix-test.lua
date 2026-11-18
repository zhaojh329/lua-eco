#!/usr/bin/env eco

local eco = require 'eco'
local file = require 'eco.file'
local socket = require 'eco.socket'
local sys = require 'eco.sys'
local test = require 'test'
local websocket = require 'eco.websocket'

local path = string.format('/tmp/eco-http-unix-test-%d.sock', sys.getpid())
if file.access(path) then
    os.remove(path)
end

test.run_case_async('http server on unix socket', function()
    local pid, err = sys.spawn(function()
        local http = require 'eco.http.server'
        local websocket = require 'eco.websocket'

        local function handler(con, req)
            if req.path == '/ws' then
                local ws, upgrade_err = websocket.upgrade(con, req)
                assert(ws, upgrade_err)
                assert(ws:send_text('hello'))
                return
            end

            assert(req.path == '/hello')
            con:add_header('content-length', '5')
            con:send('hello')
        end

        local _, listen_err = http.listen_unix(path, {
            http_keepalive = 2
        }, handler)
        assert(listen_err == nil, listen_err)
    end)
    assert(pid, err)

    for _ = 1, 100 do
        if file.access(path) then
            break
        end
        eco.sleep(0.01)
    end
    assert(file.access(path), 'unix HTTP socket was not created')

    local client, connect_err = socket.connect_unix(path)
    assert(client, connect_err)

    local request = table.concat({
        'GET /hello HTTP/1.1',
        'Host: localhost',
        'Connection: close',
        '',
        ''
    }, '\r\n')
    local written, write_err = client:send(request, 1.0)
    assert(written == #request, write_err)

    local response, read_err = client:read(4096, 1.0)
    assert(response, read_err)
    assert(response:find('HTTP/1.1 200', 1, true))
    assert(response:find('\r\n\r\nhello', 1, true))
    client:close()

    local ws, websocket_err = websocket.connect_unix(path, '/ws', {
        timeout = 1.0
    })
    assert(ws, websocket_err)
    local frame, frame_type, frame_err = ws:recv_frame(1.0)
    assert(frame == 'hello' and frame_type == 'text', frame_err)
    ws:send_close(1000, 'done')

    local kill_ok, kill_err = sys.kill(pid, sys.SIGKILL)
    assert(kill_ok, kill_err)
    for _ = 1, 100 do
        local waited_pid = sys.waitpid(pid)
        if waited_pid == pid then
            break
        end
        eco.sleep(0.01)
    end
end)

if file.access(path) then
    os.remove(path)
end

print('http unix tests passed')
