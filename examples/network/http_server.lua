#!/usr/bin/env eco

local http = require 'eco.http.server'
local log = require 'eco.log'

log.set_level(log.DEBUG)

local function handle_upload(con, req)
    local f

    while true do
        local typ, data = con:read_formdata(req)
        if typ == 'header' then
            if data[1] == 'content-disposition' then
                local filename = data[2]:match('filename="(.+)"')
                if not filename then
                    return con:send_error(http.STATUS_BAD_REQUEST)
                end

                f = io.open(filename, 'w')
                if not f then
                    return con:send_error(http.STATUS_FORBIDDEN)
                end
            end
        elseif typ == 'body' then
            if not f then
                return con:send_error(http.STATUS_BAD_REQUEST)
            end

            f:write(data[1])

            if data[2] then
                f:close()
            end
        elseif typ == 'end' then
            break
        end

        if not typ then
            return con:send_error(http.STATUS_BAD_REQUEST)
        end
    end
end

local function handler(con, req)
    if req.path == '/upload' then
        handle_upload(con, req)
    elseif req.path == '/test' then
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
