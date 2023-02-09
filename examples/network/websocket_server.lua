#!/usr/bin/env eco

local websocket = require 'eco.websocket'
local http = require 'eco.http'

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
            console.log('onopen:')
            console.log(evt)
        }

        ws.onmessage = function(evt) {
            console.log('onmessage:')
            console.log(evt)
        }

        ws.onclose = function(evt) {
            console.log('Connection closed:')
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
        if (ws) {
            ws.close()
            ws = null
        }
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
        local ws, err = websocket.upgrade(con, req)
        if not ws then
            print(err)
            return
        end

        while true do
            local msg, typ, err = ws:recv_frame()
            if not msg then
                print(err)
                return
            end
            print(typ, msg)

            ws:send_text('I am eco')
        end
    end
end

local srv, err = http.listen(nil, 8080, nil, handler)
if not srv then
    print(err)
    return
end
