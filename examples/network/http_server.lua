#!/usr/bin/env eco

local http = require 'eco.http'
local log = require 'eco.log'

log.set_level(log.DEBUG)

local function handler(con, req)
    if req.path == '/test' then
        con:add_header('content-type', 'text/html')

        con:send('<h1>Lua-eco HTTP server test</h1>\n')

        con:send('<h2>remote addr: ', req.remote_addr, '</h2>\n')
        con:send('<h2>remote port: ', req.remote_port, '</h2>\n')
        con:send('<h2>method: ', req.method, '</h2>\n')
        con:send('<h2>path: ', req.path, '</h2>\n')
        con:send('<h2>http version: ', req.major_version .. '.' .. req.minor_version, '</h2>\n')

        con:send('<h2>query:', '</h2>\n')
        for name, value in pairs(req.query) do
            con:send('<p>', name, ': ', value, '</p>\n')
        end

        con:send('<h2>headers:', '</h2>\n')
        for name, value in pairs(req.headers) do
            con:send('<p>', name, ': ', value, '</p>\n')
        end

        con:send('<h2>body:', con:read_body() or '', '</h2>\n')
    else
        con:serve_file(req)
    end
end

local options = {
    reuseaddr = true,
    reuseport = true,
    http_keepalive = 30,
    tcp_keepalive = 5,
    tcp_nodelay = true,
    docroot = '.',
    index = 'index.html',
    gzip = false
}

-- https
-- options.cert = 'cert.pem'
-- options.key = 'key.pem'

local srv, err = http.listen(nil, 8080, options, handler)
if not srv then
    print(err)
    return
end
