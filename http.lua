--[[
 * MIT License
 *
 * Copyright (c) 2022 Jianhui Zhao <zhaojh329@gmail.com>
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
--]]

local socket = require 'eco.socket'
local ssl = require 'eco.ssl'
local dns = require 'eco.dns'
local url = require 'eco.url'

local M = {}

local function send_http_request(s, method, path, headers, body)
    local data = string.format('%s %s HTTP/1.1\r\n', method, path)

    for name, value in pairs(headers) do
        data = data .. name .. ': ' .. value .. '\r\n'
    end

    data = data .. '\r\n'

    local _, err = s:send(data)
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

local function recv_http_status_line(s)
    local data, err = s:recv('*l', 3.0)
    if not data then
        return nil, err
    end

    local code, status = data:match('^HTTP/1.1 (%d+) ([^\r]+)')
    if not code or not status then
        return nil, 'invalid http response'
    end

    return code, status
end

local function recv_http_headers(s)
    local headers = {}

    while true do
        local data, err = s:recv('*l', 3.0)
        if not data then
            return nil, err
        end

        if data == '' then
            break
        end

        local name, value = data:match('([^%s:]+)%s*:%s+([^\r]+)')
        if not name or not value then
            return nil, 'invalid http response'
        end

        headers[name:lower()] = value
    end

    return headers
end

local function recv_http_chunk(s, length)
    local chunk = {}
    while length > 0 do
        local data, err = s:recv(length, 3.0)
        if not data then
            return nil, err
        end
        chunk[#chunk + 1] = data
        length = length - #data
    end

    local _, err = s:recv('*l', 3.0)
    if err then
        return nil, err
    end

    return table.concat(chunk)
end

local function recv_http_body(s, content_length, chunked)
    local body = {}

    if content_length > 0 then
        while content_length > 0 do
            local data, err = s:recv(content_length, 3.0)
            if not data then
                return nil, err
            end
            body[#body + 1] = data
            content_length = content_length - #data
        end
    elseif chunked then
        while true do
            local data, err = s:recv('*l', 3.0)
            if not data then
                return nil, err
            end

            local size = tonumber(data, 16)
            if size == 0 then
                _, err = s:recv('*l', 3.0)
                if err then
                    return nil, err
                end
                break
            end

            local chunk, err = recv_http_chunk(s, size)
            if not chunk then
                return nil, err
            end

            body[#body + 1] = chunk
        end
    end

    return table.concat(body)
end

local function do_http_request(s, method, path, headers, body)
    local ok, err = send_http_request(s, method, path, headers, body)
    if not ok then
        return nil, err
    end

    local code, status = recv_http_status_line(s)
    if not code then
        return nil, status
    end

    headers, err = recv_http_headers(s)
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
        return resp
    end

    local content_length = tonumber(headers['content-length'] or 0)
    local chunked = headers['transfer-encoding'] == 'chunked'
    body, err = recv_http_body(s, content_length, chunked)
    if not body then
        return nil, err
    end

    resp.body = body
    return resp
end

local function parse_url(u)
    local info, err = url.parse(u)
    if not info then
        return nil, err
    end

    local scheme = info.scheme

    if scheme ~= 'http' and scheme ~= 'https' then
        return nil, 'unsupported scheme: ' .. scheme
    end

    local port = info.port

    if not port then
        if scheme == 'http' then
            port = 80
        elseif scheme == 'https' then
            port = 443
        end
    end

    return scheme, info.host, port, info.raw_path
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
function M.request(req, body)
    if type(req) == 'string' then
        req = { url = req }
    end

    local scheme, host, port, path = parse_url(req.url)
    if not scheme then
        return nil, host
    end

    local answers, err = dns.query(host)
    if not answers then
        return nil, 'resolve "' .. host .. '" fail: ' .. err
    end

    local ipaddr

    for _, a in ipairs(answers) do
        if a.type == dns.TYPE_A then
            ipaddr = a.address
            break
        end
    end

    if not ipaddr then
        return nil, 'resolved 0 address for "' .. host .. '"'
    end

    local method = req.method and req.method:upper() or 'GET'

    if body then
        method = 'POST'
    end

    local headers = {
        ['User-Agent'] = 'Lua-eco/' .. eco.VERSION,
        ['Connection'] = 'close'
    }

    headers['Host'] = host

    if port ~= 80 and port ~= 443 then
        headers['Host'] = host .. ':' .. port
    end

    if body then
        headers["Content-Length"] = #body
        headers['Content-Type'] = 'application/x-www-form-urlencoded'
    end

    for k, v in pairs(req.headers or {}) do
        headers[k] = v
    end

    local s, err

    if scheme == 'http' then
        s, err = socket.connect_tcp(ipaddr, port)
    else
        s, err = ssl.connect(ipaddr, port)
    end

    if not s then
        return nil, 'connect fail: ' .. err
    end

    local resp, err = do_http_request(s, method, path, headers, body)
    if not resp then
        s:close()
        return nil, err
    end

    return resp
end

return M
