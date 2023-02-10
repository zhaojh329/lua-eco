#!/usr/bin/env eco

local http = require 'eco.http'

local function handler(con, req)
    print(string.format('new request from %s:%d', req.remote_addr, req.remote_port))

    if req.path == '/test' then
        con:add_header('content-type', 'text/html')

        con:send('<h1>Lua-eco HTTP server test</h1>\n')

        con:send('<h2>method: ', http.method_string(req.method), '</h2>\n')
        con:send('<h2>path: ', req.path, '</h2>\n')
        con:send('<h2>http version: ', req.http_version, '</h2>\n')

        con:send('<h2>query:', '</h2>\n')
        for name, value in pairs(req.query) do
            con:send('<p>', name, ': ', value, '</p>\n')
        end

        con:send('<h2>headers:', '</h2>\n')
        for name, value in pairs(req.headers) do
            con:send('<p>', name, ': ', value, '</p>\n')
        end

        con:send('<h2>body:', con:read_body(), '</h2>\n')
    else
        con:serve_file(req, {
            docroot = '.',
            index = 'index.html',
            gzip = false
        })
    end
end

local function logger(msg)
    -- print(msg)
end

local options = {
    http_keepalive = 30,
    tcp_keepalive = 5,
    tcp_nodelay = true,
    ipv6 = false
}

-- https
-- options.cert = 'cert.pem'
-- options.key = 'key.pem'

local srv, err = http.listen(nil, 8080, options, handler, logger)
if not srv then
    print(err)
    return
end
