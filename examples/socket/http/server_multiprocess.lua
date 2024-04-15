#!/usr/bin/env eco

local http = require 'eco.http.server'
local time = require 'eco.time'
local log = require 'eco.log'
local sys = require 'eco.sys'

log.set_level(log.DEBUG)

local function handler(con, req)
    if req.path == '/test' then
        con:add_header('content-type', 'text/html')

        con:send('<h1>Lua-eco HTTP server test</h1>\n')

        local remote_addr = con:remote_addr()
        con:send('<h2>remote addr: ', remote_addr.ipaddr, '</h2>\n')
        con:send('<h2>remote port: ', remote_addr.port, '</h2>\n')
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
        return con:serve_file(req)
    end
end

local options = {
    reuseaddr = true,
    reuseport = true
}

local function http_server()
    local srv, err = http.listen(nil, 8080, options, handler)
    if not srv then
        print(err)
        return
    end
end

for _ = 1, sys.get_nprocs() do
    sys.spawn(http_server)
end

while true do
    time.sleep(1)
end
