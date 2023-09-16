-- SPDX-License-Identifier: MIT
-- Author: Jianhui Zhao <zhaojh329@gmail.com>

local base64 = require 'eco.encoding.base64'
local file = require 'eco.core.file'
local socket = require 'eco.socket'
local sys = require 'eco.core.sys'
local URL = require 'eco.http.url'
local ssl = require 'eco.ssl'
local dns = require 'eco.dns'

local concat = table.concat
local tonumber = tonumber
local rand = math.random

local M = {}

local BODY_FILE_MT = 'eco-http-body-file'

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

local function send_http_request(sock, method, path, headers, body)
    local data = {}

    data[#data + 1] = string.format('%s %s HTTP/1.1\r\n', method, path)

    build_http_headers(data, headers)

    data[#data + 1] = '\r\n'

    local _, err = sock:send(concat(data))
    if err then
        return false, err
    end

    if not body then
        return true
    end

    if type(body) == 'string' then
        local _, err = sock:send(body)
        if err then
            return false, 'send body fail: ' .. err
        end
    else
        local fd, err = file.open(body.name)
        if not fd then
            return false, 'open body file fail: ' .. err
        end

        local data

        while true do
            data, err = file.read(fd, 4096)
            if not data then
                err = 'read body file fail: ' .. err
                break
            end

            if #data == 0 then
                break
            end

            _, err = sock:send(data)
            if err then
                err = 'send body fail: ' .. err
                break
            end
        end

        file.close(fd)

        if err then
            return false, err
        end
    end

    return true
end

local function recv_status_line(sock, timeout)
    local data, err = sock:recv('*l', timeout)
    if not data then
        return nil, err
    end

    local code, status = data:match('^HTTP/1.1%s*(%d+)%s*(.*)')
    if not code or not status then
        return nil, 'invalid http status line'
    end

    return tonumber(code), status
end

local function recv_http_headers(sock, timeout)
    local headers = {}

    while true do
        local data, err = sock:recv('*l', timeout)
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

local function receive_body(resp, sock, length, timeout, body_to_fd)
    local body = {}

    while length > 0 do
        local data, err = sock:recv(length > 4096 and 4096 or length, timeout)
        if not data then
            return false, 'read body fail: ' .. err
        end

        length = length - #data

        if body_to_fd then
            file.write(body_to_fd, data)
        else
            body[#body+1] = data
        end
    end

    if not body_to_fd then
        resp.body = concat(body)
    end

    return true
end

local function receive_chunked_body(resp, sock, timeout, body_to_fd)
    local deadtime = sys.uptime() + timeout
    local chunk_size
    local body = {}

    while true do
        -- first read chunk size
        local data, err = sock:recv('*l', deadtime and deadtime - sys.uptime())
        if not data then
            return nil, err
        end

        if not data:match('^%x+$') then
            return nil, 'not a vaild http chunked body'
        end

        chunk_size = tonumber(data, 16)

        if chunk_size == 0 then
            if not body_to_fd then
                resp.body = concat(body)
            end
            return true
        end

        -- second read chunk data
        local data, err = sock:recvfull(chunk_size, deadtime and deadtime - sys.uptime())
        if not data then
            return nil, err
        end

        if body_to_fd then
            file.write(body_to_fd, data)
        else
            body[#body + 1] = data
        end

        data, err = sock:recv('*l', deadtime and deadtime - sys.uptime())
        if not data then
            return nil, err
        end
    end
end

local function do_http_request(sock, method, path, headers, body, opts)
    local ok, err = send_http_request(sock, method, path, headers, body)
    if not ok then
        return nil, err
    end

    local timeout = opts.timeout

    if not timeout or timeout <= 0 then
        timeout = 30
    end

    local code, status = recv_status_line(sock, timeout)
    if not code then
        return nil, status
    end

    headers, err = recv_http_headers(sock, timeout)
    if not headers then
        return nil, err
    end

    local resp = {
        code = code,
        status = status,
        headers = headers
    }

    if method == 'HEAD' or code == 101 then
        return resp
    end

    local chunked = headers['transfer-encoding'] == 'chunked'
    local content_length

    if not chunked and headers['content-length'] then
        content_length = tonumber(headers['content-length'])
    end

    if chunked or content_length then
        local body_to_file = opts.body_to_file
        local body_to_fd

        if body_to_file then
            body_to_fd, err = file.open(body_to_file,
                file.O_WRONLY | file.O_CREAT | file.O_TRUNC, file.S_IRUSR | file.S_IWUSR | file.S_IRGRP | file.S_IROTH)
            if not body_to_fd then
                return false, 'create "' .. body_to_file .. '" fail: ' .. err
            end
        end

        local ok
        if chunked then
            ok, err = receive_chunked_body(resp, sock, timeout, body_to_fd)
        else
            ok, err = receive_body(resp, sock, content_length, timeout, body_to_fd)
        end

        if body_to_fd then
            file.close(body_to_fd)
        end

        if not ok then
            return nil, err
        end
    end

    return resp
end

local methods = {}

function methods:close()
    local mt = getmetatable(self)
    local sock = mt.sock

    if not sock then
        return
    end

    sock:close()
    mt.sock = nil
end

function methods:sock()
    local sock = getmetatable(self).sock
    if sock then
        return sock
    end

    return nil, 'not connected'
end

local schemes = {
    http = {
        default_port = 80
    },
    https = {
        default_port = 443,
        use_ssl = true
    },
    ws = {
        default_port = 80
    },
    wss = {
        default_port = 443,
        use_ssl = true
    }
}

function methods:request(method, url, body, opts)
    opts = opts or {}

    local u, err = URL.parse(url)
    if not u then
        return nil, err
    end

    local scheme, host, port, path = u.scheme, u.host, u.port, u.raw_path

    local scheme_info = schemes[scheme]
    if not scheme_info then
        return nil, 'unsupported scheme: ' .. scheme
    end

    local headers = {
        ['user-agent'] = 'Lua-eco/' .. eco.VERSION
    }

    if not port then
        port = scheme_info.default_port
    end

    if port ~= 80 and port ~= 443 then
        headers['host'] = host .. ':' .. port
    else
        headers['host'] = host
    end

    if scheme == 'http' or scheme == 'https' then
        headers['connection'] = 'close'
    else
        headers['connection'] = 'upgrade'
        headers['upgrade'] = 'websocket'
        headers['sec-websocket-version'] = '13'

        local bytes = string.char(rand(256) - 1, rand(256) - 1, rand(256) - 1,
                                rand(256) - 1, rand(256) - 1, rand(256) - 1,
                                rand(256) - 1, rand(256) - 1, rand(256) - 1,
                                rand(256) - 1, rand(256) - 1, rand(256) - 1,
                                rand(256) - 1, rand(256) - 1, rand(256) - 1,
                                rand(256) - 1)

        headers['sec-websocket-key'] = base64.encode(bytes)
    end

    if body then
        headers["content-length"] = type(body) == 'string' and #body or body.size
        headers['content-type'] = 'text/plain'
    end

    for k, v in pairs(opts.headers or {}) do
        headers[k:lower()] = v
    end

    local answers, err = dns.query(host, { type = opts.ipv6 and dns.TYPE_AAAA or dns.TYPE_A })
    if not answers then
        return nil, 'resolve "' .. host .. '" fail: ' .. err
    end

    local addresses = {}

    for _, a in ipairs(answers) do
        if a.type == dns.TYPE_A or a.type == dns.TYPE_AAAA then
            addresses[#addresses + 1] = a
        end
    end

    if #addresses < 1 then
        return nil, 'resolve "' .. host .. '" fail: not found'
    end

    local sock

    for _, a in ipairs(addresses) do
        local connect = socket.connect_tcp
        if scheme_info.use_ssl then
            connect = ssl.connect
        end

        if a.type == dns.TYPE_AAAA then
            connect = socket.connect_tcp6
            if scheme_info.use_ssl then
                connect = ssl.connect6
            end
        end

        sock, err = connect(a.address, port, opts.insecure)
        if sock then
            break
        end

        if a.type == dns.TYPE_A then
            err = string.format('connect "%s:%d" fail: ', a.address, port) .. err
        else
            err = string.format('connect "[%s]:%d" fail: ', a.address, port) .. err
        end
    end

    if not sock then
        return nil, err
    end

    self:close()

    getmetatable(self).sock = sock

    return do_http_request(sock, method, path, headers, body, opts)
end

function M.new()
    return setmetatable({}, {
        __index = methods,
        __gc = methods.close
    })
end

local function body_is_file(body)
    return type(body) == 'table' and getmetatable(body).name == BODY_FILE_MT
end

--[[
    method: HTTP request method, such as "GET", "POST".
    url: HTTP request url, such as "http://test.com", "https://test.com", "ws://test.com", "wss://test.com".
    body: HTTP request body, can be a string or a table created by method "body_with_file".
    opts: A table contains some options:
        timeout: A number, defaults to 30s.
        insecure: A boolean, SSL connecting with insecure.
        ipv6: A boolean, parse ipv6 address for host.
        body_to_file: A string indicates that the body is to be written to the file.

    In case of failure, the function returns nil followed by an error message.
    If successful, returns a table contains the
    following fields:
        body: response body as a string;
        code: response status code;
        status: response status;
        headers: response headers as a table.
--]]
function M.request(method, url, body, opts)
    if body then
        if type(body) ~= 'string' and not body_is_file(body) then
            return nil, 'invalid body'
        end
    end

    local c = M.new()
    local resp, err = c:request(method, url, body, opts)
    c:close()

    if resp then
        return resp
    end

    return nil, err
end

function M.get(url, opts)
    return M.request('GET', url, nil, opts)
end

function M.post(url, body, opts)
    return M.request('POST', url, body, opts)
end

function M.body_with_file(name)
    local st, err = file.stat(name)
    if not st then
        return nil, err
    end

    if st.type ~= 'REG' then
        return nil, 'not a regular file'
    end

    if not file.access(name, 'r') then
        return nil, 'no permission for read'
    end

    local o = {
        name = name,
        size = st.size
    }

    return setmetatable(o, { name = BODY_FILE_MT })
end

return M
