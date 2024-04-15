#!/usr/bin/env eco

local websocket = require 'eco.websocket'

local ws, err = websocket.connect('ws://127.0.0.1:8080/ws')
if not ws then
    print('failed to connect: ' .. err)
    return
end

local bytes, err = ws:send_text('Hello')
if not bytes then
    print('failed to send frame: ', err)
    return
end

local data, typ, err = ws:recv_frame()
if not data then
    print('failed to receive the frame: ', err)
    return
end

print('received: ', data, ' (', typ, '): ', err)

local bytes, err = ws:send_close(1000, 'bye')
if not bytes then
    print('failed to send frame: ', err)
    return
end
