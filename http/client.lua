-- SPDX-License-Identifier: MIT
-- Author: Jianhui Zhao <zhaojh329@gmail.com>

local socket = require 'eco.socket'
local URL = require 'eco.http.url'
local bufio = require 'eco.bufio'
local file = require 'eco.file'
local eco = require 'eco'

local concat = table.concat
local tonumber = tonumber

--- HTTP/HTTPS/WebSocket client.
--
-- This module provides a simple HTTP/1.1 client with optional TLS support.
--
-- Supported URL schemes:
--
-- - `http`, `https`
-- - `ws`, `wss` (HTTP upgrade handshake only)
--
-- For `https`/`wss`, this module uses @{eco.ssl.connect} internally and sets
-- `opts.server_name` to the URL host for SNI.
--
-- @module eco.http.client

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
        return nil, err
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
        return nil, 'send body fail: ' .. err
    end

    return true
end

local function recv_status_line(b, timeout)
    local data, err = b:read('l', timeout)
    if not data then
        return nil, err
    end

    local code, status = data:match('^HTTP/1.[01] +(%d+) +([%w%p ]*)\r?$')
    if not code or not status then
        return nil, 'invalid http status line'
    end

    return tonumber(code), status
end

local function recv_http_headers(b, timeout)
    local headers = {}

    while true do
        local data, err = b:read('l', timeout)
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

local function receive_body_until_closed(resp, b, timeout, body_to_file)
    local body = {}

    while true do
        local data = b:read(4096, timeout)
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

local function receive_body(resp, b, timeout, length, body_to_file)
    local body = {}

    while length > 0 do
        local data, err = b:read(length > 4096 and 4096 or length, timeout)
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

local function receive_chunked_body(resp, b, timeout, body_to_file)
    local chunk_size
    local body = {}

    while true do
        -- first read chunk size
        local data, err = b:read('l', timeout)
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
        data, err = b:readfull(chunk_size, timeout)
        if not data then
            return nil, err
        end

        if body_to_file then
            body_to_file:write(data)
        else
            body[#body + 1] = data
        end

        data, err = b:read('l', timeout)
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

    local b = bufio.new(sock)

    local code, status = recv_status_line(b, timeout)
    if not code then
        return nil, status
    end

    headers, err = recv_http_headers(b, timeout)
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
        ok, err = receive_chunked_body(resp, b, timeout, body_to_file)
    elseif headers['content-length'] then
        local content_length = tonumber(headers['content-length'])
        ok, err = receive_body(resp, b, timeout, content_length, body_to_file)
    else
        ok, err = receive_body_until_closed(resp, b, timeout, body_to_file)
    end

    if body_to_file then
        body_to_file:close()
    end

    if not ok then
        return nil, err
    end

    return resp
end

---
-- HTTP client object returned by @{new}.
--
-- @type client
local methods = {}

--- Close the underlying connection.
--
-- @function client:close
function methods:close()
    local sock = self.__sock

    if not sock then
        return
    end

    sock:close()
    self.sock = nil
end

--- Get the underlying connected socket.
--
-- @function client:sock
-- @treturn socket sock
-- @treturn[2] nil When not connected.
-- @treturn[2] string Error message.
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

local function generate_websocket_key()
    local base64 = require 'eco.encoding.base64'
    local random = math.random
    local bytes = {}

    for i = 1, 16 do
        bytes[i] = string.char(random(0, 255))
    end

    return base64.encode(table.concat(bytes))
end

--- Perform a request using this client.
--
-- For `https`/`wss`, TLS options in `opts` are passed to @{eco.ssl.connect}.
--
-- @function client:request
-- @tparam string method HTTP method.
-- @tparam string url Request URL.
-- @tparam[opt] string|body_file|body_form body Request body.
-- @tparam[opt] table opts See @{request}.
-- @treturn table resp
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
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
        headers['sec-websocket-key'] = generate_websocket_key()
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

    local addresses = {}

    if socket.is_ip_address(host) then
        addresses[1] = host
    else
        local dns = require 'eco.dns'
        local answers, err = dns.query(host, {
            type = opts.ipv6 and dns.TYPE_AAAA or dns.TYPE_A,
            mark = opts.mark,
            device = opts.device,
            nameservers = opts.nameservers
        })
        if not answers then
            return nil, 'resolve "' .. host .. '" fail: ' .. err
        end

        for _, a in ipairs(answers) do
            if a.type == dns.TYPE_A or a.type == dns.TYPE_AAAA then
                addresses[#addresses + 1] = a.address
            end
        end

        if #addresses < 1 then
            return nil, 'resolve "' .. host .. '" fail: not found'
        end
    end

    local sock

    for _, address in ipairs(addresses) do
        if scheme_info.use_ssl then
            local ssl = require 'eco.ssl'
            opts.server_name = host
            sock, err = ssl.connect(address, port, opts)
        else
            sock, err = socket.connect_tcp(address, port, opts)
        end

        if sock then
            break
        end

        err = string.format('connect "%s %d" fail: ', address, port) .. err
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
    __gc = methods.close,
    __close = methods.close
}

--- End of `client` class section.
-- @section end

--- Create a new HTTP client.
--
-- @function new
-- @treturn client
function M.new()
    return setmetatable({}, metatable)
end

--- Perform an HTTP request.
--
-- This is a convenience wrapper that creates a temporary client, performs the
-- request, and closes the connection.
--
-- `opts` options commonly used:
--
-- - `timeout` (number) request timeout in seconds (default 30).
-- - `headers` (table) extra request headers.
-- - `body_to_file` (string) write response body to the given file path.
-- - `ipv6` (boolean) resolve AAAA records.
-- - `mark` (number) SO_MARK for sockets.
-- - `device` (string) SO_BINDTODEVICE for sockets.
-- - `nameservers` (table) DNS servers (see @{eco.dns.query}).
-- - TLS: `ca`, `cert`, `key`, `insecure` (passed to @{eco.ssl.connect}).
--
-- @function request
-- @tparam string method HTTP method, e.g. `"GET"`, `"POST"`.
-- @tparam string url Request URL.
-- @tparam[opt] string|body_file|body_form body Request body.
-- @tparam[opt] table opts Options table.
-- @treturn table resp Response table:
--
-- - `code` (number)
-- - `status` (string)
-- - `headers` (table)
-- - `body` (string) (omitted when `body_to_file` is used)
--
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
function M.request(method, url, body, opts)
    if body then
        if type(body) ~= 'string' and not body_is_file(body) and not body_is_form(body) then
            return nil, 'invalid body'
        end
    end

    if body_is_form(body) and body.length == 0 then
        body = nil
    end

    local c<close> = M.new()

    return c:request(method, url, body, opts)
end

--- Convenience wrapper for `GET`.
-- @function get
-- @tparam string url
-- @tparam[opt] table opts See @{request}.
-- @treturn table resp
-- @treturn[2] nil
-- @treturn[2] string Error message.
function M.get(url, opts)
    return M.request('GET', url, nil, opts)
end

--- Convenience wrapper for `POST`.
-- @function post
-- @tparam string url
-- @tparam[opt] string|body_file|body_form body
-- @tparam[opt] table opts See @{request}.
-- @treturn table resp
-- @treturn[2] nil
-- @treturn[2] string Error message.
function M.post(url, body, opts)
    return M.request('POST', url, body, opts)
end

--- File body descriptor returned by @{body_with_file}.
--
-- @type body_file
local body_file_mt = { name = BODY_FILE_MT }

--- End of `body_file` class section.
-- @section end

--- Use a file as request body.
--
-- The returned object can be used as the `body` argument of @{request}.
--
-- @function body_with_file
-- @tparam string name File path.
-- @treturn body_file body
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
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

--- Multipart form body returned by @{form}.
--
-- @type body_form

local form_methods = {}

--- Add a simple form field.
--
-- @function body_form:add
-- @tparam string name Field name.
-- @tparam string value Field value.
-- @treturn boolean true
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

--- Add a file field.
--
-- @function body_form:add_file
-- @tparam string name Field name.
-- @tparam string path File path.
-- @treturn boolean true On success.
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
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

--- End of `body_form` class section.
-- @section end

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

--- Create a multipart form body.
--
-- The returned object can be used as the `body` argument of @{request}.
--
-- @function form
-- @treturn body_form
function M.form()
    local boundary = generate_boundary()
    return setmetatable({ boundary = boundary, length = 0, contents = {} }, form_metatable)
end

return M
