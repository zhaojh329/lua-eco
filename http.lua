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
local file = require 'eco.file'
local time = require 'eco.time'
local ssl = require 'eco.ssl'
local dns = require 'eco.dns'

local str_format = string.format
local str_lower = string.lower
local tonumber = tonumber

local M = {
    HTTP_STATUS_CONTINUE = 100,
    HTTP_STATUS_SWITCHING_PROTOCOLS = 101,
    HTTP_STATUS_PROCESSING = 102,
    HTTP_STATUS_OK = 200,
    HTTP_STATUS_CREATED = 201,
    HTTP_STATUS_ACCEPTED = 202,
    HTTP_STATUS_NON_AUTHORITATIVE_INFORMATION = 203,
    HTTP_STATUS_NO_CONTENT = 204,
    HTTP_STATUS_RESET_CONTENT = 205,
    HTTP_STATUS_PARTIAL_CONTENT = 206,
    HTTP_STATUS_MULTI_STATUS = 207,
    HTTP_STATUS_ALREADY_REPORTED = 208,
    HTTP_STATUS_IM_USED = 226,
    HTTP_STATUS_MULTIPLE_CHOICES = 300,
    HTTP_STATUS_MOVED_PERMANENTLY = 301,
    HTTP_STATUS_FOUND = 302,
    HTTP_STATUS_SEE_OTHER = 303,
    HTTP_STATUS_NOT_MODIFIED = 304,
    HTTP_STATUS_USE_PROXY = 305,
    HTTP_STATUS_TEMPORARY_REDIRECT = 307,
    HTTP_STATUS_PERMANENT_REDIRECT = 308,
    HTTP_STATUS_BAD_REQUEST = 400,
    HTTP_STATUS_UNAUTHORIZED = 401,
    HTTP_STATUS_PAYMENT_REQUIRED = 402,
    HTTP_STATUS_FORBIDDEN = 403,
    HTTP_STATUS_NOT_FOUND = 404,
    HTTP_STATUS_METHOD_NOT_ALLOWED = 405,
    HTTP_STATUS_NOT_ACCEPTABLE = 406,
    HTTP_STATUS_PROXY_AUTHENTICATION_REQUIRED = 407,
    HTTP_STATUS_REQUEST_TIMEOUT = 408,
    HTTP_STATUS_CONFLICT = 409,
    HTTP_STATUS_GONE = 410,
    HTTP_STATUS_LENGTH_REQUIRED = 411,
    HTTP_STATUS_PRECONDITION_FAILED = 412,
    HTTP_STATUS_PAYLOAD_TOO_LARGE = 413,
    HTTP_STATUS_URI_TOO_LONG = 414,
    HTTP_STATUS_UNSUPPORTED_MEDIA_TYPE = 415,
    HTTP_STATUS_RANGE_NOT_SATISFIABLE = 416,
    HTTP_STATUS_EXPECTATION_FAILED = 417,
    HTTP_STATUS_MISDIRECTED_REQUEST = 421,
    HTTP_STATUS_UNPROCESSABLE_ENTITY = 422,
    HTTP_STATUS_LOCKED = 423,
    HTTP_STATUS_FAILED_DEPENDENCY = 424,
    HTTP_STATUS_UPGRADE_REQUIRED = 426,
    HTTP_STATUS_PRECONDITION_REQUIRED = 428,
    HTTP_STATUS_TOO_MANY_REQUESTS = 429,
    HTTP_STATUS_REQUEST_HEADER_FIELDS_TOO_LARGE = 431,
    HTTP_STATUS_UNAVAILABLE_FOR_LEGAL_REASONS = 451,
    HTTP_STATUS_INTERNAL_SERVER_ERROR = 500,
    HTTP_STATUS_NOT_IMPLEMENTED = 501,
    HTTP_STATUS_BAD_GATEWAY = 502,
    HTTP_STATUS_SERVICE_UNAVAILABLE = 503,
    HTTP_STATUS_GATEWAY_TIMEOUT = 504,
    HTTP_STATUS_HTTP_VERSION_NOT_SUPPORTED = 505,
    HTTP_STATUS_VARIANT_ALSO_NEGOTIATES = 506,
    HTTP_STATUS_INSUFFICIENT_STORAGE = 507,
    HTTP_STATUS_LOOP_DETECTED = 508,
    HTTP_STATUS_NOT_EXTENDED = 510,
    HTTP_STATUS_NETWORK_AUTHENTICATION_REQUIRED = 511,

    HTTP_METHOD_GET = 0,
    HTTP_METHOD_POST = 1,
    HTTP_METHOD_PUT = 2,
    HTTP_METHOD_HEAD = 3,
    HTTP_METHOD_DELETE = 4,
    HTTP_METHOD_CONNECT = 5,
    HTTP_METHOD_OPTIONS = 6,
    HTTP_METHOD_TRACE = 7,
    HTTP_METHOD_PATCH = 8
}

local status_map = {
    [M.HTTP_STATUS_CONTINUE] = 'Continue',
    [M.HTTP_STATUS_SWITCHING_PROTOCOLS] = 'Switching Protocols',
    [M.HTTP_STATUS_PROCESSING] = 'Processing',
    [M.HTTP_STATUS_OK] = 'OK',
    [M.HTTP_STATUS_CREATED] = 'Created',
    [M.HTTP_STATUS_ACCEPTED] = 'Accepted',
    [M.HTTP_STATUS_NON_AUTHORITATIVE_INFORMATION] = 'Non-Authoritative Information',
    [M.HTTP_STATUS_NO_CONTENT] = 'No Content',
    [M.HTTP_STATUS_RESET_CONTENT] = 'Reset Content',
    [M.HTTP_STATUS_PARTIAL_CONTENT] = 'Partial Content',
    [M.HTTP_STATUS_MULTI_STATUS] = 'Multi-Status',
    [M.HTTP_STATUS_ALREADY_REPORTED] = 'Already Reported',
    [M.HTTP_STATUS_IM_USED] = 'IM Used',
    [M.HTTP_STATUS_MULTIPLE_CHOICES] = 'Multiple Choices',
    [M.HTTP_STATUS_MOVED_PERMANENTLY] = 'Moved Permanently',
    [M.HTTP_STATUS_FOUND] = 'Found',
    [M.HTTP_STATUS_SEE_OTHER] = 'See Other',
    [M.HTTP_STATUS_NOT_MODIFIED] = 'Not Modified',
    [M.HTTP_STATUS_USE_PROXY] = 'Use Proxy',
    [M.HTTP_STATUS_TEMPORARY_REDIRECT] = 'Temporary Redirect',
    [M.HTTP_STATUS_PERMANENT_REDIRECT] = 'Permanent Redirect',
    [M.HTTP_STATUS_BAD_REQUEST] = 'Bad Request',
    [M.HTTP_STATUS_UNAUTHORIZED] = 'Unauthorized',
    [M.HTTP_STATUS_PAYMENT_REQUIRED] = 'Payment Required',
    [M.HTTP_STATUS_FORBIDDEN] = 'Forbidden',
    [M.HTTP_STATUS_NOT_FOUND] = 'Not Found',
    [M.HTTP_STATUS_METHOD_NOT_ALLOWED] = 'Method Not Allowed',
    [M.HTTP_STATUS_NOT_ACCEPTABLE] = 'Not Acceptable',
    [M.HTTP_STATUS_PROXY_AUTHENTICATION_REQUIRED] = 'Proxy Authentication Required',
    [M.HTTP_STATUS_REQUEST_TIMEOUT] = 'Request Timeout',
    [M.HTTP_STATUS_CONFLICT] = 'Conflict',
    [M.HTTP_STATUS_GONE] = 'Gone',
    [M.HTTP_STATUS_LENGTH_REQUIRED] = 'Length Required',
    [M.HTTP_STATUS_PRECONDITION_FAILED] = 'Precondition Failed',
    [M.HTTP_STATUS_PAYLOAD_TOO_LARGE] = 'Payload Too Large',
    [M.HTTP_STATUS_URI_TOO_LONG] = 'URI Too Long',
    [M.HTTP_STATUS_UNSUPPORTED_MEDIA_TYPE] = 'Unsupported Media Type',
    [M.HTTP_STATUS_RANGE_NOT_SATISFIABLE] = 'Range Not Satisfiable',
    [M.HTTP_STATUS_EXPECTATION_FAILED] = 'Expectation Failed',
    [M.HTTP_STATUS_MISDIRECTED_REQUEST] = 'Misdirected Request',
    [M.HTTP_STATUS_UNPROCESSABLE_ENTITY] = 'Unprocessable Entity',
    [M.HTTP_STATUS_LOCKED] = 'Locked',
    [M.HTTP_STATUS_FAILED_DEPENDENCY] = 'Failed Dependency',
    [M.HTTP_STATUS_UPGRADE_REQUIRED] = 'Upgrade Required',
    [M.HTTP_STATUS_PRECONDITION_REQUIRED] = 'Precondition Required',
    [M.HTTP_STATUS_TOO_MANY_REQUESTS] = 'Too Many Requests',
    [M.HTTP_STATUS_REQUEST_HEADER_FIELDS_TOO_LARGE] = 'Request Header Fields Too Large',
    [M.HTTP_STATUS_UNAVAILABLE_FOR_LEGAL_REASONS] = 'Unavailable For Legal Reasons',
    [M.HTTP_STATUS_INTERNAL_SERVER_ERROR] = 'Internal Server Error',
    [M.HTTP_STATUS_NOT_IMPLEMENTED] = 'Not Implemented',
    [M.HTTP_STATUS_BAD_GATEWAY] = 'Bad Gateway',
    [M.HTTP_STATUS_SERVICE_UNAVAILABLE] = 'Service Unavailable',
    [M.HTTP_STATUS_GATEWAY_TIMEOUT] = 'Gateway Timeout',
    [M.HTTP_STATUS_HTTP_VERSION_NOT_SUPPORTED] = 'HTTP Version Not Supported',
    [M.HTTP_STATUS_VARIANT_ALSO_NEGOTIATES] = 'Variant Also Negotiates',
    [M.HTTP_STATUS_INSUFFICIENT_STORAGE] = 'Insufficient Storage',
    [M.HTTP_STATUS_LOOP_DETECTED] = 'Loop Detected',
    [M.HTTP_STATUS_NOT_EXTENDED] = 'Not Extended',
    [M.HTTP_STATUS_NETWORK_AUTHENTICATION_REQUIRED] = 'Network Authentication Required'
}

local mime_map = {
    ['txt'] = 'text/plain',
    ['log'] = 'text/plain',
    ['lua'] = 'text/plain',
    ['js'] = 'text/javascript',
    ['css'] = 'text/css',
    ['htm'] = 'text/html',
    ['html'] = 'text/html',
    ['diff'] = 'text/x-patch',
    ['patch'] = 'text/x-patch',
    ['c'] = 'text/x-csrc',
    ['h'] = 'text/x-chdr',
    ['o'] = 'text/x-object',
    ['ko'] = 'text/x-object',

    ['bmp'] = 'image/bmp',
    ['gif'] = 'image/gif',
    ['png'] = 'image/png',
    ['jpg'] = 'image/jpeg',
    ['jpeg'] = 'image/jpeg',
    ['svg'] = 'image/svg+xml',

    ['json'] = 'application/json',
    ['jsonp'] = 'application/javascript',
    ['zip'] = 'application/zip',
    ['pdf'] = 'application/pdf',
    ['xml'] = 'application/xml',
    ['xsl'] = 'application/xml',
    ['doc'] = 'application/msword',
    ['ppt'] = 'application/vnd.ms-powerpoint',
    ['xls'] = 'application/vnd.ms-excel',
    ['odt'] = 'application/vnd.oasis.opendocument.text',
    ['odp'] = 'application/vnd.oasis.opendocument.presentation',
    ['pl'] = 'application/x-perl',
    ['sh'] = 'application/x-shellscript',
    ['php'] = 'application/x-php',
    ['deb'] = 'application/x-deb',
    ['iso'] = 'application/x-cd-image',
    ['tar.gz'] = 'application/x-compressed-tar',
    ['tgz'] = 'application/x-compressed-tar',
    ['gz'] = 'application/x-gzip',
    ['tar.bz2'] = 'application/x-bzip-compressed-tar',

    ['tbz'] = 'application/x-bzip-compressed-tar',
    ['bz2'] = 'application/x-bzip',
    ['tar'] = 'application/x-tar',
    ['rar'] = 'application/x-rar-compressed',

    ['mp3'] = 'audio/mpeg',
    ['ogg'] = 'audio/x-vorbis+ogg',
    ['wav'] = 'audio/x-wav',

    ['mpg'] = 'video/mpeg',
    ['mpeg'] = 'video/mpeg',
    ['avi'] = 'video/x-msvideo',

    ['README'] = 'text/plain',
    ['md'] = 'text/plain',
    ['cfg'] = 'text/plain',
    ['conf'] = 'text/plain'
}

local month_abbr_map = {
    Jan  = 1,
    Feb = 2,
    Mar = 3,
    Apr = 4,
    May = 5,
    Jun = 6,
    Jul = 7,
    Aug = 8,
    Sep = 9,
    Oct = 10,
    Nov = 11,
    Dec = 12
}

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

    local _, err = s:send(table.concat(data))
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

local function recv_http_status_line(s, deadtime)
    local data, err = s:recv('*l', deadtime - time.now())
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
        local data, err = s:recv('*l', deadtime - time.now())
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

local function recv_http_body(s, content_length, chunked, deadtime)
    local body = {}

    if content_length > 0 then
        while content_length > 0 do
            local data, err = s:recv(content_length, deadtime - time.now())
            if not data then
                return nil, err
            end
            body[#body + 1] = data
            content_length = content_length - #data
        end
    elseif chunked then
        while true do
            local data, err = s:recv('*l', deadtime - time.now())
            if not data then
                return nil, err
            end

            if not data:match('^%x+$') then
                return nil, 'not a vaild http chunked body'
            end

            local size = tonumber(data, 16)
            local remain = size
            local chunk = {}

            while remain > 0 do
                data, err = s:recv(remain, deadtime - time.now())
                if not data then
                    return nil, err
                end
                remain = remain - #data
                chunk[#chunk + 1] = data
            end

            data, err = s:recv('*l', deadtime - time.now())
            if err then
                return nil, err
            end

            if data ~= '' then
                return nil, 'not a vaild http chunked body'
            end

            body[#body + 1] = table.concat(chunk)

            if size == 0 then break end
        end
    end

    return table.concat(body)
end

local function do_http_request(s, method, path, headers, body, timeout)
    local ok, err = send_http_request(s, method, path, headers, body)
    if not ok then
        return nil, err
    end

    if not timeout or timeout <= 0 then
        timeout = 30
    end

    local deadtime = time.now() + timeout

    local code, status = recv_http_status_line(s, deadtime)
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
        return resp
    end

    local content_length = tonumber(headers['content-length'] or 0)
    local chunked = headers['transfer-encoding'] == 'chunked'
    body, err = recv_http_body(s, content_length, chunked, deadtime)
    if not body then
        return nil, err
    end

    resp.body = body
    return resp
end

-- <scheme>://<user>:<password>@<host>:<port>/<path>;<params>?<query>#<frag>
local function parse_url(url)
    if not url then
        return nil, 'invalid url'
    end

    local parsed = {}

    url = string.gsub(url, '^%a%w*://', function(s)
        parsed.scheme = s:match('%a%w*')
        return ''
    end)

    if not parsed.scheme then
        return nil, 'invalid url'
    end

    url = string.gsub(url, '^[^:@]+:[^:@]+@', function(s)
        parsed.user, parsed.password = s:match('([^:]+):([^@]+)')
        return ''
    end)

    url = string.gsub(url, '^([^@]+)@', function(s)
        parsed.user = s
        return ''
    end)

    url = string.gsub(url, '^[^:/?#]+', function(s)
        parsed.host = s
        return ''
    end)

    if not parsed.host then
        return nil, 'invalid url'
    end

    url = string.gsub(url, '^:(%d+)', function(s)
        parsed.port = tonumber(s)
        return ''
    end)

    if url:sub(1, 1) ~= '/' then
        url = '/' .. url
    end

    parsed.raw_path = url

    url = string.gsub(url, '^/[^;?#]*', function(s)
        parsed.path = s
        return ''
    end)

    url = string.gsub(url, ';([^;?#]*)', function(s)
        parsed.params = s
        return ''
    end)

    url = string.gsub(url, '?([^;?#]*)', function(s)
        parsed.query = s
        return ''
    end)

    url = string.gsub(url, '#([^;?#]*)$', function(s)
        parsed.frag = s
        return ''
    end)

    return parsed
end

local function http_connect_host(host, port, https)
    local answers, err = dns.query(host)
    if not answers then
        return nil, 'resolve "' .. host .. '" fail: ' .. err
    end

    local s, err
    for _, a in ipairs(answers) do
        if a.type == dns.TYPE_A or a.type == dns.TYPE_AAAA then
            local connect = socket.connect_tcp
            if https then
                connect = ssl.connect
            end

            if a.type == dns.TYPE_AAAA then
                connect = socket.connect_tcp6
                if https then
                    connect = ssl.connect6
                end
            end

            s, err = connect(a.address, port)
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
function M.request(req, body)
    if type(req) == 'string' then
        req = { url = req }
    end

    local url, err = parse_url(req.url)
    if not url then
        return nil, err
    end

    local scheme, host, port, path = url.scheme, url.host, url.port, url.raw_path

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
        s, err = http_connect_host(host, port, scheme == 'https')
        if not s then
            return nil, 'connect fail: ' .. err
        end
    end

    local resp, err = do_http_request(s, method, path, headers, body, req.timeout)
    s:close()
    return resp, err
end

local con_methods = {}

function con_methods:closed()
    return getmetatable(self).sock:closed()
end

function con_methods:add_header(name, value)
    local resp = getmetatable(self).resp
    resp.headers[name:lower()] = value
end

function con_methods:set_status(code, status)
    local resp = getmetatable(self).resp

    if resp.head_sent then
        error('http head has been sent')
    end

    resp.code = code

    if status then
        resp.status = status
    end

    return true
end

local function send_http_head(resp)
    if resp.head_sent then return end

    local data = resp.data

    local code = resp.code
    local status = resp.status

    status = status or status_map[code]

    data[#data + 1] = string.format('HTTP/1.1 %d', code)

    if status then
        data[#data + 1] = ' ' .. status
    end

    data[#data + 1] = '\r\n'

    build_http_headers(data, resp.headers)

    data[#data + 1] = '\r\n'

    resp.head_sent = true
end

function con_methods:send_error(code, status, content)
    local mt = getmetatable(self)

    if mt.sock:closed() then
        return false, 'closed'
    end

    self:set_status(code, status)
    self:add_header('connection', 'close')

    if content then
        self:send(content)
    else
        send_http_head(mt.resp)
    end

    return true
end

function con_methods:send(...)
    local mt = getmetatable(self)
    local resp = mt.resp

    if mt.sock:closed() then
        return false, 'closed'
    end

    local data = table.concat({...})
    local len = #data
    if len == 0 then
        return true
    end

    if not resp.head_sent then
        self:add_header('transfer-encoding', 'chunked')
        send_http_head(resp)
    end

    local rdata = resp.data

    rdata[#rdata + 1] = string.format('%x\r\n', len)
    rdata[#rdata + 1] = data
    rdata[#rdata + 1] = '\r\n'

    resp.has_body = true
    return true
end

local function http_send_file(sock, fd, size, count, offset)
    if offset and offset > -1 then
        size = size - offset
    end

    count = count or size

    if count > size then
        count = size
    end

    local _, err = sock:send(string.format('%x\r\n', count))
    if err then
        return false, err
    end

    local _, err = sock:sendfile(fd, count, offset)
    if err then
        return false, err
    end

    local _, err = sock:send('\r\n')
    if err then
        return false, err
    end

    return true
end

function con_methods:send_file_fd(fd, size, count, offset)
    local mt = getmetatable(self)
    local options = mt.options
    local resp = mt.resp
    local sock = mt.sock

    assert(not options.ssl, 'not support sendfile for https')

    if count and count < 1 then
        return true
    end

    if not resp.head_sent then
        self:add_header('transfer-encoding', 'chunked')
        send_http_head(resp)
    end

    local ok, err = self:flush()
    if not ok then
        return false, err
    end

    ok, err = http_send_file(sock, fd, size, count, offset)
    if not ok then
        sock:close()
        return false, err
    end

    resp.has_body = true
    return true
end

function con_methods:send_file(path, count, offset)
    local mt = getmetatable(self)
    local options = mt.options

    assert(not options.ssl, 'not support sendfile for https')

    if mt.sock:closed() then
        return false, 'closed'
    end

    if count and count < 1 then
        return true
    end

    local st, err = file.stat(path)
    if not st then
        return false, err
    end

    if st.type ~= 'REG' then
        return false, 'forbidden'
    end

    local fd, err = file.open(path)
    if not fd then
        return false, err
    end

    local ok, err = self:send_file_fd(fd, st.size, count, offset)
    file.close(fd)

    return ok, err
end

function con_methods:flush()
    local mt = getmetatable(self)
    local resp = mt.resp
    local sock = mt.sock
    local data = resp.data

    if not resp.head_sent then
        send_http_head(resp)
    end

    if #data == 0 then
        return true
    end

    local _, err = sock:send(table.concat(data))
    if err then
        sock:close()
        return false, err
    end

    resp.data = {}

    return true
end

function con_methods:read_body(count, timeout)
    local mt = getmetatable(self)
    local body_remain = mt.body_remain
    local sock = mt.sock

    if sock:closed() then
        return nil, 'closed'
    end

    timeout = timeout or 3.0

    count = count or body_remain
    if count > body_remain then
        count = body_remain
    end

    if count < 1 then
        return ''
    end

    local data, err = sock:recv(count, timeout)
    if not data then
        sock:close()
        return nil, err
    end

    mt.body_remain = mt.body_remain - #data

    return data
end

function con_methods:discard_body()
    local mt = getmetatable(self)
    local body_remain = mt.body_remain
    local sock = mt.sock

    while body_remain > 0 do
        local data, err = sock:recv(body_remain, 3.0)
        if not data then
            return false, err
        end
        body_remain = body_remain - #data
    end

    return true
end

function con_methods:serve_file(req, options)
    local mt = getmetatable(self)
    local path = req.path
    local phy_path

    if mt.sock:closed() then
        return false, 'closed'
    end

    options = options or {}

    if path == '/' then
        phy_path = options.docroot .. options.index
    else
        phy_path = options.docroot .. path
    end

    local suffix = phy_path:match('(%w+)$') or ''
    local gzip = options.gzip

    if gzip then
        if suffix ~= 'gz' and file.access(phy_path .. '.gz', 'r') then
            phy_path = phy_path .. '.gz'
        else
            gzip = false
        end
    end

    if not gzip then
        if not file.access(phy_path) then
            return self:send_error(M.HTTP_STATUS_NOT_FOUND)
        end

        if not file.access(phy_path, 'r') then
            return self:send_error(M.HTTP_STATUS_FORBIDDEN)
        end
    end

    local st, err = file.stat(phy_path)
    if not st then
        return self:send_error(M.HTTP_STATUS_INTERNAL_SERVER_ERROR, nil, string.format('stat "%s" fail: %s', phy_path, err))
    end

    if st.type ~= 'REG' then
        return self:send_error(M.HTTP_STATUS_FORBIDDEN)
    end

    if req.method ~= M.HTTP_METHOD_GET and req.method ~= M.HTTP_METHOD_HEAD then
        return self:send_error(M.HTTP_STATUS_METHOD_NOT_ALLOWED)
    end

    local etag = string.format('%x-%x', st.ino, st.size)
    self:add_header('etag', etag)
    self:add_header('last-modified', os.date('%a, %d %b %Y %H:%M:%S GMT', st.mtime))

    if req.headers['if-none-match'] == etag then
        return self:set_status(M.HTTP_STATUS_NOT_MODIFIED)
    end

    if req.headers['if-modified-since'] then
        local day, month, year, hour, min, sec = req.headers['if-modified-since']:match('^%a+, (%d%d) (%a+) (%d%d%d%d) (%d%d):(%d%d):(%d%d) GMT$')
        if day and month and month_abbr_map[month] and year and hour and min and sec then
            local t = os.time({
                year = year,
                month = month_abbr_map[month],
                day = day,
                hour = hour,
                min = min,
                sec = sec
            })

            if t >= st.mtime then
                return self:set_status(M.HTTP_STATUS_NOT_MODIFIED)
            end
        end
    end

    self:add_header('content-type', mime_map[suffix] or 'application/octet-stream')

    if gzip then
        self:add_header('content-encoding', 'gzip')
    end

    if req.method == M.HTTP_METHOD_HEAD then
        return true
    end

    local fd, err = file.open(phy_path)
    if not fd then
        return self:send_error(M.HTTP_STATUS_INTERNAL_SERVER_ERROR, nil, string.format('open "%s" fail: %s', phy_path, err))
    end

    local ok, err, data

    if mt.options.ssl then
        while true do
            data, err = file.read(fd, 4096)
            if not data then
                break
            end

            if #data == 0 then
                ok = true
                break
            end

            self:send(data)
        end
    else
        ok, err = self:send_file_fd(fd, st.size)
    end

    file.close(fd)

    return ok, err
end

local function http_con_log_info(addr, msg)
    local s = debug.getinfo(2, 'Sl')
    local str = os.date() .. ' ' .. s.short_src .. ':' .. s.currentline

    if addr then
        str = str .. str_format(' %s:%d', addr.ipaddr, addr.port)
    end

    return  str .. ' ' .. msg
end

local function handle_connection(con, peer, handler, first)
    local mt = getmetatable(con)
    local sock = mt.sock

    local http_keepalive = mt.options.http_keepalive

    local method, path, ver

    while true do
        local data, err = sock:recv('*l', first and 3.0 or http_keepalive)
        if not data then
            return false, http_con_log_info(peer, 'before request received: ' .. err)
        end

        if #data > 0 then
            local method_str
            method_str, path, ver = data:match('^(%u+)%s+(%S+)%s+HTTP/(%d%.%d)$')
            if not method_str or not path or not ver then
                return false,  http_con_log_info(peer, 'not a vaild http request start line')
            end

            method = M['HTTP_METHOD_' .. method_str]
            if not method then
                return false, http_con_log_info(peer, 'not supported http method "' .. method_str .. '"')
            end

            if ver ~= '1.1' then
                return false, http_con_log_info(peer, 'not supported http version ' .. ver)
            end

            break
        end

        --ignore any empty line(s) received where a Request-Line is expected.
    end

    local headers = {}

    while true do
        local data, err = sock:recv('*l', 3.0)
        if not data then
            return false, http_con_log_info(peer, 'not a complete http request: ' .. err)
        end

        if data == '' then
            break
        end

        local name, value = data:match('^([%w-_]+):%s*(.+)$')
        if not name or not value then
            return false, http_con_log_info(peer, 'not a vaild http header')
        end

        headers[str_lower(name)] = value
    end

    if str_lower(headers['transfer-encoding'] or '') == 'chunked' then
        return false, http_con_log_info(peer, 'not support chunked http request')
    end

    local query_string = ''

    path = path:gsub('%?(.*)', function(s)
        query_string = s
        return ''
    end)

    local query = {}

    for q in query_string:gmatch('[^&]+') do
        local name, value = q:match('(.+)=(.+)')
        if name then
            query[name] = value
        end
    end

    mt.body_remain = tonumber(headers['content-length'] or 0)

    local resp = {
        code = 200,
        headers = {
            server = 'Lua-eco/' .. eco.VERSION,
            date = os.date('!%a, %d %b %Y %H:%M:%S GMT')
        },
        data = {}
    }
    mt.resp = resp

    local req = {
        remote_addr = peer.ipaddr,
        remote_port = peer.port,
        method = method,
        path = path,
        http_version = tonumber(ver),
        headers = headers,
        query = query
    }

    handler(con, req)

    if sock:closed() then
        return false, http_con_log_info(peer, 'closed')
    end

    if resp.has_body then
        local data = resp.data
        data[#data + 1] = '0\r\n'
        data[#data + 1] = '\r\n'
    end

    local ok, err = con:flush()
    if not ok then
        return false, http_con_log_info(peer, 'flush data: ' .. err)
    end

    local req_connection = str_lower(req.headers['connection'] or '')
    local resp_connection = str_lower(resp.headers['connection'] or '')

    if http_keepalive < 1 or req_connection == 'close'
        or req_connection == 'upgrade'
        or resp_connection == 'close' then
        sock:close()
    else
        ok, err = con:discard_body()
        if not ok then
            return false, http_con_log_info(peer, 'discard body: ' .. err)
        end
    end

    return true
end

function M.listen(ipaddr, port, options, handler, logger)
    options = options or {}

    options.docroot = options.docroot or '.'

    if options.docroot ~= '/' then
        options.docroot = options.docroot:gsub('/$', '')
    end

    options.index = options.index or 'index.html'
    options.http_keepalive = options.http_keepalive or 30

    local sock, err

    if options.cert and options.key then
        options.ssl = true
        if options.ipv6 then
            sock, err = ssl.listen6(ipaddr, port, { cert = options.cert, key = options.key })
        else
            sock, err = ssl.listen(ipaddr, port, { cert = options.cert, key = options.key })
        end
    else
        if options.ipv6 then
            sock, err = socket.listen_tcp6(ipaddr, port)
        else
            sock, err = socket.listen_tcp(ipaddr, port)
        end
    end
    if not sock then
        return nil, err
    end

    while true do
        local c, peer = sock:accept()
        if c then
            if logger then
                logger(http_con_log_info(peer, 'new connection'))
            end

            eco.run(function(c)
                local first = true

                local con = setmetatable({}, {
                    sock = c,
                    resp = {
                        code = 200,
                        headers = {
                            server = 'Lua-eco/' .. eco.VERSION
                        }
                    },
                    options = options,
                    __index = con_methods
                })

                while not c:closed() do
                    local ok, err = handle_connection(con, peer, handler, first)
                    if not ok then
                        if logger then
                            logger(err)
                        end
                        c:close()
                    end
                    first = false
                end
            end, c)
        else
            if logger then
                logger(http_con_log_info(nil, 'accept: ' .. peer))
            end
        end
    end
end

function M.method_string(method)
    local methods = {
        [M.HTTP_METHOD_GET] = 'GET',
        [M.HTTP_METHOD_POST] = 'POST',
        [M.HTTP_METHOD_PUT] = 'PUT',
        [M.HTTP_METHOD_HEAD] = 'HEAD',
        [M.HTTP_METHOD_DELETE] = 'DELETE',
        [M.HTTP_METHOD_CONNECT] = 'CONNECT',
        [M.HTTP_METHOD_OPTIONS] = 'OPTIONS',
        [M.HTTP_METHOD_TRACE] = 'TRACE',
        [M.HTTP_METHOD_PATCH] = 'PATCH'
    }

    return methods[method] or ''
end

return M
