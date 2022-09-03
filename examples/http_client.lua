#!/usr/bin/env lua

local eco = require "eco"
local ssl = require "eco.ssl"
local dns = require "eco.dns"
local socket = require "eco.socket"
local hp = require "eco.http_parser"

local function http_get(url)
    local url_info = hp.parse_url(url)

    if not url_info.schema then
        return nil, "invalid url"
    end

    if url_info.port == 0 then
        if url_info.schema == "https" then
            url_info.port = 443
        else
            url_info.port = 80
        end
    end

    local resolver = dns.resolver()
    local ipaddrs, err = resolver:query(url_info.host)
    if not ipaddrs or #ipaddrs == 0 then
        return nil, "resolve fail"
    end

    if url_info.port ~= 80 and url_info.port ~= 443 then
        url_info.host = url_info.host .. ":" .. url_info.port
    end

    local s = socket.tcp()
    local ok, err = s:connect(ipaddrs[1], url_info.port)
    if not ok then
        return nil, "connect:" .. err
    end

    local ssl_ctx, ssl_session
    local c

    if url_info.schema == "https" then
        ssl_ctx = ssl.context()
        ssl_session = ssl_ctx:new(s:getfd(), true)
        c = ssl_session
    else
        c = s
    end

    c:write("GET " .. (url_info.path or "/") .. " HTTP/1.1\r\n")
    c:write("Host: " .. url_info.host .. "\r\n")
    c:write("User-Agent: lua-eco/" .. eco.VERSION .. "\r\n")
    c:write("Accept: */*\r\n")
    c:write("\r\n")

    local done = false
    local body = {}
    local headers = {}
    local cur_header_name

    local settings = {
        on_header_field = function(data)
            cur_header_name = data
        end,
        on_header_value = function(data)
            headers[cur_header_name] = data
        end,
        on_body = function(data)
            body[#body + 1] = data
        end,
        on_message_complete = function()
            done = true
        end
    }

    local parser = hp.response(settings)

    while not done do
        local data, err = c:read()
        if not data then
            return nil, "read fail:" .. err
        end

        parser:execute(data)
    end

    local http_major, http_minor = parser:http_version()

    local res = {
        ver = http_major .. '.' ..  http_minor,
        status = parser:status_code(),
        headers = headers,
        body = table.concat(body)
    }

    return res
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
