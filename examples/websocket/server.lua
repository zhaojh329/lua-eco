#!/usr/bin/env eco

local websocket = require 'eco.websocket'
local http = require 'eco.http.server'

local page =
[[
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>Lua-eco Websocket test</title>
<script>
    var ws

    function connect() {
        if (ws) {
            alert('already connected')
            return
        }

        ws = new WebSocket('ws://' + location.host + '/ws')

        ws.onopen = function(evt) {
            console.log(evt)
        }

        ws.onmessage = function(evt) {
            console.log(evt)
        }

        ws.onclose = function(evt) {
            console.log(evt)
            ws = null
        }
    }

    function send() {
        if (!ws) {
            alert('disconnected')
            return
        }
        ws.send('Hello WebSockets!')
    }

    function disconnect() {
        if (ws)
            ws.close(1000, 'byte!')
    }
</script>
</head>
<body>
    <button onclick="connect()">Connect</button>
    <button onclick="send()">Send</button>
    <button onclick="disconnect()">Disconnect</button>
</body>
</html>
]]

local function handler(con, req)
    local path = req.path

    if path == '/' then
        con:add_header('content-type', 'text/html')
        con:send(page)
    elseif path == '/ws' then
        local opts = {
            max_payload_len = 65535
        }
        local ws, err = websocket.upgrade(con, req, opts)
        if not ws then
            print(err)
            return
        end

        while true do
            local data, typ, err = ws:recv_frame()
            if not data then
                print('err:', err)
                return
            end

            if typ == 'close' then
                -- for typ 'close', err contains the status code
                local code = err

                -- send a close frame back:
                ws:send_close(1000, 'enough, enough!')
                print('closing with status code ' .. code .. ' and message "' .. data .. '"')
                return
            end

            if typ == 'ping' then
                ws:send_pong(data)
            elseif typ == 'pong' then
                -- just discard the incoming pong frame
            else
                print('received a frame of type "' .. typ .. '" and payload "' .. data .. '"')
            end

            ws:send_text('Hello world')
            ws:send_binary('blah blah blah...')
        end
    end
end

local srv, err = http.listen(nil, 8080, { reuseaddr = true }, handler)
if not srv then
    print(err)
    return
end
