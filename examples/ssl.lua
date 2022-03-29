#!/usr/bin/env lua

local eco = require "eco"
local ssl = require "eco.ssl"
local socket = require "eco.socket"

local ctx = ssl.context(true)
if not ctx:load_crt_file("cert.pem") then
    error("load crt file fail")
end

if not ctx:load_key_file("key.pem") then
    error("load key file fail")
end

-- curl -k https://127.0.0.1:8080
eco.run(
    function()
        local s = socket.tcp()
        s:bind(nil, 8080)
        s:listen()

        while true do
            local c = s:accept()

            local ss = ctx:new(c:getfd(), true)

            eco.run(
                function()
                    while true do
                        local data = ss:read()
                        if not data then break end

                        local msg = "Hello, I'm lua-eco\n"

                        ss:write("HTTP/1.1 200 OK\r\n")
                        ss:write("Content-Length: " .. #msg .. "\r\n")
                        ss:write("\r\n")
                        ss:write(msg)
                    end
                end
            )
        end
    end
)

eco.loop()
