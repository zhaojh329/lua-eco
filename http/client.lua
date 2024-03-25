-- SPDX-License-Identifier: MIT
-- Author: Jianhui Zhao <zhaojh329@gmail.com>

local base64 = require 'eco.encoding.base64'
local socket = require 'eco.socket'
local URL = require 'eco.http.url'
local file = require 'eco.file'
local ssl = require 'eco.ssl'
local dns = require 'eco.dns'

local concat = table.concat
local tonumber = tonumber
local rand = math.random

local M = {}

local BODY_FILE_MT = 'eco-http-body-file'
local BODY_FORM_MT = 'eco-http-body-form'

local function body_is_file(body)
    return type(body) == 'table' and getmetatable(body).name == BODY_FILE_MT
end

local function body_is_form(body)
    return type(body) == 'table' and getmetatable(body).name == BODY_FORM_MT
end

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
        _, err = sock:send(body)
    elseif body_is_file(body) then
        _, err = sock:sendfile(body.name, body.size)
    elseif body_is_form(body) then
        for _, content in ipairs(body.contents) do
            if type(content) == 'string' then
                _, err = sock:send(content)
            else
                _, err = sock:sendfile(content.path, content.size)
            end

            if err then break end
        end
    end

    if err then
        return false, 'send body fail: ' .. err
    end

    return true
end

local function recv_status_line(sock, timeout)
    local data, err = sock:recv('l', timeout)
    if not data then
        return nil, err
    end

    local code, status = data:match('^HTTP/1.1 +(%d+) +([%w%p ]*)\r?$')
    if not code or not status then
        return nil, 'invalid http status line'
    end

    return tonumber(code), status
end

local function recv_http_headers(sock, timeout)
    local headers = {}

    while true do
        local data, err = sock:recv('l', timeout)
        if not data then
            return nil, err
        end

        if data == '\r' or data == '' then break end

        local name, value = data:match('([%w%p]+) *: *([%w%p ]+)\r?$')
        if not name or not value then
            return nil, 'invalid http header'
        end

        headers[name:lower()] = value
    end

    return headers
end

local function receive_body_until_closed(resp, sock, timeout, body_to_file)
    local body = {}

    while true do
        local data = sock:recv(4096, timeout)
        if not data then
            break
        end

        if body_to_file then
            body_to_file:write(data)
        else
            body[#body+1] = data
        end
    end

    if not body_to_file then
        resp.body = concat(body)
    end

    return true
end

local function receive_body(resp, sock, timeout, length, body_to_file)
    local body = {}

    while length > 0 do
        local data, err = sock:recv(length > 4096 and 4096 or length, timeout)
        if not data then
            return false, 'read body fail: ' .. err
        end

        length = length - #data

        if body_to_file then
            body_to_file:write(data)
        else
            body[#body+1] = data
        end
    end

    if not body_to_file then
        resp.body = concat(body)
    end

    return true
end

local function receive_chunked_body(resp, sock, timeout, body_to_file)
    local chunk_size
    local body = {}

    while true do
        -- first read chunk size
        local data, err = sock:recv('l', timeout)
        if not data then
            return nil, err
        end

        data = data:match('^%x+\r?')
        if not data then
            return nil, 'not a vaild http chunked body'
        end

        chunk_size = tonumber(data, 16)

        if chunk_size == 0 then
            if not body_to_file then
                resp.body = concat(body)
            end
            return true
        end

        -- second read chunk data
        data, err = sock:readfull(chunk_size, timeout)
        if not data then
            return nil, err
        end

        if body_to_file then
            body_to_file:write(data)
        else
            body[#body + 1] = data
        end

        data, err = sock:recv('l', timeout)
        if not data then
            return nil, err
        end
    end
end

local function do_http_request(self, method, path, headers, body, opts)
    local sock = self:sock()

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

    local body_to_file = opts.body_to_file

    if body_to_file then
        local f, err = io.open(body_to_file, 'w')
        if not f then
            return false, 'create "' .. body_to_file .. '" fail: ' .. err
        end
        body_to_file = f
    end

    if headers['transfer-encoding'] == 'chunked' then
        ok, err = receive_chunked_body(resp, sock, timeout, body_to_file)
    elseif headers['content-length'] then
        local content_length = tonumber(headers['content-length'])
        ok, err = receive_body(resp, sock, timeout, content_length, body_to_file)
    else
        ok, err = receive_body_until_closed(resp, sock, timeout, body_to_file)
    end

    if body_to_file then
        body_to_file:close()
    end

    if not ok then
        return nil, err
    end

    return resp
end

local methods = {}

function methods:close()
    local sock = self.__sock

    if not sock then
        return
    end

    sock:close()
    self.sock = nil
end

function methods:sock()
    local sock = self.__sock
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
        if body_is_form(body) then
            local contents = body.contents
            contents[#contents + 1] = '--' .. body.boundary .. '--\r\n'
            body.length = body.length + #contents[#contents]

            headers['content-type'] = 'multipart/form-data; boundary=' .. body.boundary
            headers["content-length"] = body.length
        else
            headers['content-type'] = 'text/plain'
            headers["content-length"] = type(body) == 'string' and #body or body.size
        end
    end

    for k, v in pairs(opts.headers or {}) do
        headers[k:lower()] = v
    end

    local answers, err = dns.query(host, {
        type = opts.ipv6 and dns.TYPE_AAAA or dns.TYPE_A,
        mark = opts.mark,
        device = opts.device,
        nameservers = opts.nameservers
    })
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
        opts.ipv6 = a.type == dns.TYPE_AAAA

        if scheme_info.use_ssl then
            sock, err = ssl.connect(a.address, port, opts)
        else
            sock, err = socket.connect_tcp(a.address, port, opts)
        end

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

    self.__sock = sock

    return do_http_request(self, method, path, headers, body, opts)
end

local metatable = {
    __index = methods,
    __gc = methods.close
}

function M.new()
    return setmetatable({}, metatable)
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
        mark: a number used to set SO_MARK to socket
        device: a string used to set SO_BINDTODEVICE to socket
        nameservers: see dns.query

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
        if type(body) ~= 'string' and not body_is_file(body) and not body_is_form(body) then
            return nil, 'invalid body'
        end
    end

    if body_is_form(body) and body.length == 0 then
        body = nil
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

local body_file_mt = { name = BODY_FILE_MT }

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

    return setmetatable(o, body_file_mt)
end

local form_methods = {}

function form_methods:add(name, value)
    assert(type(name) == 'string')
    assert(type(value) == 'string')

    local contents = self.contents

    contents[#contents + 1] = '--' .. self.boundary .. '\r\n'
    self.length = self.length + #contents[#contents]

    contents[#contents + 1] = 'Content-Disposition: form-data; name="' .. name .. '"\r\n\r\n'
    self.length = self.length + #contents[#contents]

    contents[#contents + 1] = value .. '\r\n'
    self.length = self.length + #value + 2

    return true
end

function form_methods:add_file(name, path)
    assert(type(name) == 'string')
    assert(type(path) == 'string')

    local contents = self.contents

    local st, err = file.stat(path)
    if not st then
        return nil, err
    end

    if st.type ~= 'REG' then
        return nil, 'not a regular file'
    end

    if not file.access(path, 'r') then
        return nil, 'no permission for read'
    end

    local filename = file.basename(path)

    contents[#contents + 1] = '--' .. self.boundary .. '\r\n'
    self.length = self.length + #contents[#contents]

    contents[#contents + 1] = string.format('Content-Disposition: form-data; name="%s"; filename="%s"\r\n', name, filename)
    self.length = self.length + #contents[#contents]

    contents[#contents + 1] = 'Content-Type: application/octet-stream\r\n\r\n'
    self.length = self.length + #contents[#contents]

    contents[#contents + 1] = { path = path, size = st.size }
    self.length = self.length + st.size

    contents[#contents + 1] = '\r\n'
    self.length = self.length + 2

    return true
end

local form_metatable = {
    name = BODY_FORM_MT,
    __index = form_methods
}

local function generate_boundary()
    local characters = "0123456789abcdef"
    local boundary = {}

    for i = 1, 16 do
        local idx = math.random(1, #characters)
        boundary[i] = characters:sub(idx, idx)
    end

    return '------------------------' .. concat(boundary)
end

function M.form()
    local boundary = generate_boundary()
    return setmetatable({ boundary = boundary, length = 0, contents = {} }, form_metatable)
end

return M
