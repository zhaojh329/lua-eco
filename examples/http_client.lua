#!/usr/bin/env lua

local eco = require "eco"
local ssl = require "eco.ssl"
local dns = require "eco.dns"
local socket = require "eco.socket"

local function http_get(url)
    local scheme, host, port, path

    local scheme, url = url:match("(%a+)://(.+)")
    if not scheme or not url then
        return nil, "invalid url"
    end

    host, path = url:match('([^/]+)(.*)')
    if not path or #path == 0 then
        path = "/"
    end

    host, port = host:match('([^:]+):?(%d*)')

    if not port or #port == 0 then
        if scheme == "https" then
            port = "443"
        else
            port = "80"
        end
    end

    local resolver = dns.resolver()
    local ipaddrs, err = resolver:query(host)
    if not ipaddrs or #ipaddrs == 0 then
        return nil, "resolve fail"
    end

    if port ~= "80" and port ~= "443" then
        host = host .. ":" .. port
    end

    local s = socket.tcp()
    local ok, err = s:connect(ipaddrs[1], port)
    if not ok then
        return nil, "connect:" .. err
    end

    local ssl_ctx, ssl_session
    local c

    if scheme == "https" then
        ssl_ctx = ssl.context()
        ssl_session = ssl_ctx:new(s:getfd(), true)
        c = ssl_session
    else
        c = s
    end

    c:write("GET " .. path .. " HTTP/1.1\r\n")
    c:write("Host: " .. host .. "\r\n")
    c:write("User-Agent: lua-eco/" .. eco.VERSION .. "\r\n")
    c:write("Accept: */*\r\n")
    c:write("\r\n")

    local res = { headers = {} }

    local data, err = c:read("L")
    if not data then
        return nil, "read fail:" .. err
    end
    local ver, code, reason = data:match("HTTP/(%d%.%d)%s+(%d+)%s+(%S+)\r\n")
    if not ver or not code or not reason then
        return nil, "invalid http"
    end

    res.ver = ver
    res.status = code
    res.reason = reason

    local content_length = 0
    local chunked = false
    local body = {}

    while true do
        local data, err = c:read("L")
        if not data then
            return nil, "read fail:" .. err
        end

        if data == "\r\n" then
            if not chunked and content_length == 0 then
                return res
            end
            break
        else
            local name, value = data:match("(%S+):%s*(%C+)\r\n")
            if not name or not value then
                return nil, "invalid http"
            end

            res.headers[name] = value
            if name:lower() == "content-length" then
                content_length = tonumber(value)
            elseif name:lower() == "transfer-encoding" and value == "chunked" then
                chunked = true
            end
        end
    end

    if chunked then
        while true do
            local data, err = c:read("L")
            if not data then
                return nil, "read fail:" .. err
            end

            local size = data:match("(%x+)\r\n")
            if not size then
                return "invalid http"
            end

            size = tonumber(size, 16)
            if size == 0 then
                res.body = table.concat(body)
                return res
            end

            local buf = {}

            while size > 0 do
                local piece = 1024
                if piece > size then piece = size end
                data, err = c:read(piece)
                if not data then
                    return nil, "read fail:" .. err
                end
                size = size - #data
                buf[#buf + 1] = data
            end

            c:read(2)

            body[#body + 1] = table.concat(buf)
        end
    else
        while content_length > 0 do
            local piece = 1024
            if piece > content_length then piece = content_length end
            data, err = c:read(piece)
            if not data then
                return nil, "read fail:" .. err
            end

            content_length = content_length - #data
            body[#body + 1] = data
        end

        res.body = table.concat(body)
        return res
    end
end

eco.run(
    function()
        local res, err = http_get("https://www.baidu.com")
        if not res then
            print(err)
            return
        end

        print("http ver:", res.ver)
        print("http status:", res.status)
        print("http headers:")
        for k, v in pairs(res.headers) do
            print("", k .. ":", v)
        end

        print("http body:", res.body and #res.body)
        print(res.body)
    end
)

eco.loop()
