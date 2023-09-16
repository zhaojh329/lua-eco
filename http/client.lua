-- SPDX-License-Identifier: MIT
-- Author: Jianhui Zhao <zhaojh329@gmail.com>

local socket = require 'eco.socket'
local sys = require 'eco.core.sys'
local url = require 'eco.http.url'
local ssl = require 'eco.ssl'
local dns = require 'eco.dns'
local log = require 'eco.log'

local concat = table.concat
local tonumber = tonumber

local M = {}

local function build_http_headers(data, headers)
    for name, value in pairs(headers) do
        name = name:gsub('^.', function(s)
            return s:upper()
        end)

        name = name:gsub('-.', function(s)
            return s:upper()
        end)

        data[#data + 1] = string.format('%s: %s\r\n', name, value)
    end
end

local function send_http_request(s, method, path, headers, body)
    local data = {}

    data[#data + 1] = string.format('%s %s HTTP/1.1\r\n', method, path)

    build_http_headers(data, headers)

    data[#data + 1] = '\r\n'

    local _, err = s:send(concat(data))
    if err then
        return false, err
    end

    if body then
        local _, err = s:send(body)
        if err then
            return false, err
        end
    end

    return true
end

local function recv_status_line(s, deadtime)
    local data, err = s:recv('*l', deadtime - sys.uptime())
    if not data then
        return nil, err
    end

    local code, status = data:match('^HTTP/1.1%s*(%d+)%s*(.*)')
    if not code or not status then
        return nil, 'invalid http status line'
    end

    return tonumber(code), status
end

local function recv_http_headers(s, deadtime)
    local headers = {}

    while true do
        local data, err = s:recv('*l', deadtime - sys.uptime())
        if not data then
            return nil, err
        end

        if data == '' then break end

        local name, value = data:match('([^%s:]+)%s*:%s*([^\r]+)')
        if not name or not value then
            return nil, 'invalid http header'
        end

        headers[name:lower()] = value
    end

    return headers
end

local function body_reader(s, headers)
    local content_length = tonumber(headers['content-length'] or 0)
    local chunked = headers['transfer-encoding'] == 'chunked'

    if chunked then
        local state = 0

        return function (n, timeout)
            if s:closed() then
                return nil, 'closed'
            end

            if type(n) ~= 'number' then
                error('arg 1 must be a number')
            end

            local deadtime

            if timeout then
                deadtime = sys.uptime() + timeout
            end

            local body = {}
            local need = n

            while true do
                if state == 0 then
                    local data, err = s:recv('*l', deadtime and deadtime - sys.uptime())
                    if not data then
                        s:close()
                        return nil, err
                    end

                    if not data:match('^%x+$') then
                        s:close()
                        return nil, 'not a vaild http chunked body'
                    end

                    content_length = tonumber(data, 16)

                    if content_length == 0 then
                        s:close()
                        return concat(body)
                    end

                    state = 1
                elseif state == 1 then
                    n = need
                    if n > content_length or n < 0 then
                        n = content_length
                    end

                    local data, err, partial = s:recvfull(n, deadtime and deadtime - sys.uptime())
                    if not data then
                        s:close()
                        if partial then
                            content_length = content_length - #partial
                            body[#body + 1] = partial
                        end
                        log.err('read chunked body fail: ' .. err)
                        return concat(body)
                    end

                    content_length = content_length - #data
                    if need > 0 then
                        need = need - #data
                    end

                    body[#body + 1] = data

                    if content_length == 0 then
                        data, err = s:recv('*l', deadtime and deadtime - sys.uptime())
                        if err or data ~= '' then
                            s:close()
                            return concat(body)
                        end
                        state = 0
                    end

                    if need == 0 then
                        return concat(body)
                    end
                end
            end
        end
    end

    if content_length > 0 then
        return function (n, timeout)
            if s:closed() then
                return nil, 'closed'
            end

            if type(n) ~= 'number' then
                error('arg 1 must be a number')
            end

            if n > content_length or n < 0 then
                n = content_length
            end

            local body, err, partial = s:recvfull(n, timeout)
            if err or n == content_length then
                s:close()
            end

            if not body then
                if partial then
                    log.err(string.format('with %d bytes remaining to read: ' .. err, content_length - #partial))
                    return partial
                end
                return nil, err
            end

            content_length = content_length - #body
            return body
        end
    end

    s:close()

    return function() return '' end
end

local function do_http_request(s, method, path, headers, body, timeout)
    local ok, err = send_http_request(s, method, path, headers, body)
    if not ok then
        return nil, err
    end

    if not timeout or timeout <= 0 then
        timeout = 30
    end

    local deadtime = sys.uptime() + timeout

    local code, status = recv_status_line(s, deadtime)
    if not code then
        return nil, status
    end

    headers, err = recv_http_headers(s, deadtime)
    if not headers then
        return nil, err
    end

    local resp = {
        code = code,
        status = status,
        headers = headers,
        body = ''
    }

    if method == 'HEAD' then
        resp.read_body = function() return '' end
        return resp
    end

    resp.read_body = body_reader(s, headers)

    return resp
end

function M.connect(host, port, use_ssl, opts)
    local answers, err = dns.query(host)
    if not answers then
        return nil, 'resolve "' .. host .. '" fail: ' .. err
    end

    local s, err
    for _, a in ipairs(answers) do
        if a.type == dns.TYPE_A or a.type == dns.TYPE_AAAA then
            local connect = socket.connect_tcp
            if use_ssl then
                connect = ssl.connect
            end

            if a.type == dns.TYPE_AAAA then
                connect = socket.connect_tcp6
                if use_ssl then
                    connect = ssl.connect6
                end
            end

            if use_ssl then
                s, err = connect(a.address, port, opts.insecure)
            else
                s, err = connect(a.address, port)
            end
            if s then
                return s
            end
        end
    end

    if not err then
        err = 'resolve "' .. host .. '" fail: 0 address'
    end

    return nil, err
end

--[[
    The request function has two forms. The simple form downloads a URL using the GET or POST method and is based on strings.
    The generic form performs any HTTP method.

    If the first argument of the request function is a string, it should be an url. In that case, if a body is provided as a
    string, the function will perform a POST method in the url. Otherwise, it performs a GET in the url.

    If the first argument is instead a table, the most important fields are the url.
    The optional parameters are the following:
        method: The HTTP request method. Defaults to "GET";
        headers: Any additional HTTP headers to send with the request.

    In case of failure, the function returns nil followed by an error message. If successful, returns a table contains the
    following fields:
        body: response body as a string;
        code: response status code;
        status: response status;
        headers: response headers as a table.
--]]
function M.request(req, body, opts)
    opts = opts or {}

    if type(req) == 'string' then
        req = { url = req }
    end

    local u, err = url.parse(req.url)
    if not u then
        return nil, err
    end

    local scheme, host, port, path = u.scheme, u.host, u.port, u.raw_path

    if scheme ~= 'http' and scheme ~= 'https' then
        return nil, 'unsupported scheme: ' .. scheme
    end

    if not port then
        if scheme == 'http' then
            port = 80
        elseif scheme == 'https' then
            port = 443
        end
    end

    local method = req.method and req.method:upper() or 'GET'

    if body then
        method = 'POST'
    end

    local headers = {
        ['user-Agent'] = 'Lua-eco/' .. eco.VERSION,
        ['connection'] = 'close'
    }

    headers['host'] = host

    if port ~= 80 and port ~= 443 then
        headers['host'] = host .. ':' .. port
    end

    if body then
        headers["content-length"] = #body
        headers['content-type'] = 'application/x-www-form-urlencoded'
    end

    for k, v in pairs(req.headers or {}) do
        headers[k] = v
    end

    local s, err

    if req.proxy then
        s, err = socket.connect_tcp(req.proxy.ipaddr, req.proxy.port)
        path = req.url
    else
        s, err = M.connect(host, port, scheme == 'https', opts)
        if not s then
            return nil, 'connect fail: ' .. err
        end
    end

    local resp, err = do_http_request(s, method, path, headers, body, req.timeout)
    if err or method == 'HEAD' then
        s:close()
    end

    if err then
        return nil, err
    end

    return resp
end

return M
