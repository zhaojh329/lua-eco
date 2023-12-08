#!/usr/bin/env eco

local http = require 'eco.http.server'
local log = require 'eco.log'

log.set_level(log.DEBUG)

local function handle_upload(con, req)
    local f

    local cbs = {
        on_part_data_begin = function()
            print('on_part_data_begin')
        end,

        on_header = function(name, value)
            print('on_header:', name, value)
            if name == 'content-disposition' then
                local filename = value:match('filename="(.+)"')
                f = io.open(filename, 'w')
                if not f then
                    return false
                end
            end
        end,

        on_headers_complete = function()
            print('on_headers_complete')
        end,

        on_part_data = function(data)
            f:write(data)
        end,

        on_part_data_end = function()
            print('on_part_data_end')
            f:close()
        end
    }

    con:read_formdata(req, cbs)
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
options.cert = 'cert.pem'
options.key = 'key.pem'

local srv, err = http.listen(nil, 8080, options, handler)
if not srv then
    print(err)
    return
end
