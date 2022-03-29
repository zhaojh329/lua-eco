#!/usr/bin/env lua

local eco = require "eco"
local socket = require "eco.socket"

local function http_listen(ip, port, router)
    local s = socket.tcp()
    local ok, err = s:bind(ip, port)
    if not ok then
        return err
    end

    s:listen()

    while true do
        local c = s:accept()

        eco.run(function()
            local data = c:recv("L")
            if not data then
                c:close()
                return
            end

            local method, path, ver = data:match("(%S+)%s*(%S+)%s*HTTP/(%d%.%d)\r\n")
            if not method or not path and not ver then
                c:close()
                return
            end

            local path, query = path:match('([^?]+)%?*(.*)')
            local headers = {}

            while true do
                local data = c:recv("L")
                if not data then
                    c:close()
                    return
                end

                if data == "\r\n" then
                    break
                else
                    local name, value = data:match("(%S+):%s*(%C+)\r\n")
                    if not name or not value then
                        return
                    end

                    headers[name] = value
                end
            end

            if not router[path] then
                c:send("HTTP/1.1 404 Not Found\r\n")
                c:send("Server: lua-eco/0.0.0\r\n")
                c:send("Content-Length: 0\r\n")
                c:send("\r\n")
                c:close()
                return
            end

            router[path](c, method, query, headers)
        end)
    end
end

local router = {
    ["/test"] = function(c, method, query, headers)
        local msg = "Hello, I'm lua-eco\n"

        if method == "POST" then
            local content_length = headers["Content-Length"] or ""
            content_length = tonumber(content_length)
            local body = {}

            while content_length > 0 do
                local piece = 4096
                if piece > content_length then
                    piece = content_length
                end
                local data = c:read(piece)
                if not data then
                    break
                end
                body[#body + 1] = data
                content_length = content_length - #data
            end
            print("body:", table.concat(body))
        end

        c:send("HTTP/1.1 200 OK\r\n")
        c:send("Server: lua-eco/0.0.0\r\n")
        c:send("Content-Type: text/plain\r\n")
        c:send("Content-Length: " .. #msg .. "\r\n")
        c:send("\r\n")
        c:send(msg)
        c:close()
    end
}

eco.run(
    function()
        http_listen(nil, 8080, router)
    end
)

eco.loop()
