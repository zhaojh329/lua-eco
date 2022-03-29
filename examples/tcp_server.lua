#!/usr/bin/env lua

local eco = require "eco"
local socket = require "eco.socket"

local function handle_client(c)
    while true do
        local data, err = c:recv()
        if not data then
            print(err)
            break
        end
        c:send(data)
    end
end

eco.run(
    function()
        local s = socket.tcp()
        local ok, err = s:bind(nil, 8080)
        if not ok then
            error(err)
        end

        s:listen()

        while true do
            local c = s:accept()
            local peer = c:getpeername()
            print("new connection:", peer.ipaddr, peer.port)
            eco.run(handle_client, c)
        end
    end
)

eco.loop()
