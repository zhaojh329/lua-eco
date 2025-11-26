-- SPDX-License-Identifier: MIT
-- Author: Jianhui Zhao <zhaojh329@gmail.com>

local file = require 'eco.core.file'
local socket = require 'eco.socket'
local url = require 'eco.http.url'
local log = require 'eco.log'

local str_lower = string.lower
local str_upper = string.upper
local concat = table.concat
local tonumber = tonumber
local tostring = tostring
local assert = assert
local pairs = pairs
local type = type

local M = {
    STATUS_CONTINUE = 100,
    STATUS_SWITCHING_PROTOCOLS = 101,
    STATUS_PROCESSING = 102,
    STATUS_OK = 200,
    STATUS_CREATED = 201,
    STATUS_ACCEPTED = 202,
    STATUS_NON_AUTHORITATIVE_INFORMATION = 203,
    STATUS_NO_CONTENT = 204,
    STATUS_RESET_CONTENT = 205,
    STATUS_PARTIAL_CONTENT = 206,
    STATUS_MULTI_STATUS = 207,
    STATUS_ALREADY_REPORTED = 208,
    STATUS_IM_USED = 226,
    STATUS_MULTIPLE_CHOICES = 300,
    STATUS_MOVED_PERMANENTLY = 301,
    STATUS_FOUND = 302,
    STATUS_SEE_OTHER = 303,
    STATUS_NOT_MODIFIED = 304,
    STATUS_USE_PROXY = 305,
    STATUS_TEMPORARY_REDIRECT = 307,
    STATUS_PERMANENT_REDIRECT = 308,
    STATUS_BAD_REQUEST = 400,
    STATUS_UNAUTHORIZED = 401,
    STATUS_PAYMENT_REQUIRED = 402,
    STATUS_FORBIDDEN = 403,
    STATUS_NOT_FOUND = 404,
    STATUS_METHOD_NOT_ALLOWED = 405,
    STATUS_NOT_ACCEPTABLE = 406,
    STATUS_PROXY_AUTHENTICATION_REQUIRED = 407,
    STATUS_REQUEST_TIMEOUT = 408,
    STATUS_CONFLICT = 409,
    STATUS_GONE = 410,
    STATUS_LENGTH_REQUIRED = 411,
    STATUS_PRECONDITION_FAILED = 412,
    STATUS_PAYLOAD_TOO_LARGE = 413,
    STATUS_URI_TOO_LONG = 414,
    STATUS_UNSUPPORTED_MEDIA_TYPE = 415,
    STATUS_RANGE_NOT_SATISFIABLE = 416,
    STATUS_EXPECTATION_FAILED = 417,
    STATUS_MISDIRECTED_REQUEST = 421,
    STATUS_UNPROCESSABLE_ENTITY = 422,
    STATUS_LOCKED = 423,
    STATUS_FAILED_DEPENDENCY = 424,
    STATUS_UPGRADE_REQUIRED = 426,
    STATUS_PRECONDITION_REQUIRED = 428,
    STATUS_TOO_MANY_REQUESTS = 429,
    STATUS_REQUEST_HEADER_FIELDS_TOO_LARGE = 431,
    STATUS_UNAVAILABLE_FOR_LEGAL_REASONS = 451,
    STATUS_INTERNAL_SERVER_ERROR = 500,
    STATUS_NOT_IMPLEMENTED = 501,
    STATUS_BAD_GATEWAY = 502,
    STATUS_SERVICE_UNAVAILABLE = 503,
    STATUS_GATEWAY_TIMEOUT = 504,
    STATUS_HTTP_VERSION_NOT_SUPPORTED = 505,
    STATUS_VARIANT_ALSO_NEGOTIATES = 506,
    STATUS_INSUFFICIENT_STORAGE = 507,
    STATUS_LOOP_DETECTED = 508,
    STATUS_NOT_EXTENDED = 510,
    STATUS_NETWORK_AUTHENTICATION_REQUIRED = 511
}

local status_map = {
    [M.STATUS_CONTINUE] = 'Continue',
    [M.STATUS_SWITCHING_PROTOCOLS] = 'Switching Protocols',
    [M.STATUS_PROCESSING] = 'Processing',
    [M.STATUS_OK] = 'OK',
    [M.STATUS_CREATED] = 'Created',
    [M.STATUS_ACCEPTED] = 'Accepted',
    [M.STATUS_NON_AUTHORITATIVE_INFORMATION] = 'Non-Authoritative Information',
    [M.STATUS_NO_CONTENT] = 'No Content',
    [M.STATUS_RESET_CONTENT] = 'Reset Content',
    [M.STATUS_PARTIAL_CONTENT] = 'Partial Content',
    [M.STATUS_MULTI_STATUS] = 'Multi-Status',
    [M.STATUS_ALREADY_REPORTED] = 'Already Reported',
    [M.STATUS_IM_USED] = 'IM Used',
    [M.STATUS_MULTIPLE_CHOICES] = 'Multiple Choices',
    [M.STATUS_MOVED_PERMANENTLY] = 'Moved Permanently',
    [M.STATUS_FOUND] = 'Found',
    [M.STATUS_SEE_OTHER] = 'See Other',
    [M.STATUS_NOT_MODIFIED] = 'Not Modified',
    [M.STATUS_USE_PROXY] = 'Use Proxy',
    [M.STATUS_TEMPORARY_REDIRECT] = 'Temporary Redirect',
    [M.STATUS_PERMANENT_REDIRECT] = 'Permanent Redirect',
    [M.STATUS_BAD_REQUEST] = 'Bad Request',
    [M.STATUS_UNAUTHORIZED] = 'Unauthorized',
    [M.STATUS_PAYMENT_REQUIRED] = 'Payment Required',
    [M.STATUS_FORBIDDEN] = 'Forbidden',
    [M.STATUS_NOT_FOUND] = 'Not Found',
    [M.STATUS_METHOD_NOT_ALLOWED] = 'Method Not Allowed',
    [M.STATUS_NOT_ACCEPTABLE] = 'Not Acceptable',
    [M.STATUS_PROXY_AUTHENTICATION_REQUIRED] = 'Proxy Authentication Required',
    [M.STATUS_REQUEST_TIMEOUT] = 'Request Timeout',
    [M.STATUS_CONFLICT] = 'Conflict',
    [M.STATUS_GONE] = 'Gone',
    [M.STATUS_LENGTH_REQUIRED] = 'Length Required',
    [M.STATUS_PRECONDITION_FAILED] = 'Precondition Failed',
    [M.STATUS_PAYLOAD_TOO_LARGE] = 'Payload Too Large',
    [M.STATUS_URI_TOO_LONG] = 'URI Too Long',
    [M.STATUS_UNSUPPORTED_MEDIA_TYPE] = 'Unsupported Media Type',
    [M.STATUS_RANGE_NOT_SATISFIABLE] = 'Range Not Satisfiable',
    [M.STATUS_EXPECTATION_FAILED] = 'Expectation Failed',
    [M.STATUS_MISDIRECTED_REQUEST] = 'Misdirected Request',
    [M.STATUS_UNPROCESSABLE_ENTITY] = 'Unprocessable Entity',
    [M.STATUS_LOCKED] = 'Locked',
    [M.STATUS_FAILED_DEPENDENCY] = 'Failed Dependency',
    [M.STATUS_UPGRADE_REQUIRED] = 'Upgrade Required',
    [M.STATUS_PRECONDITION_REQUIRED] = 'Precondition Required',
    [M.STATUS_TOO_MANY_REQUESTS] = 'Too Many Requests',
    [M.STATUS_REQUEST_HEADER_FIELDS_TOO_LARGE] = 'Request Header Fields Too Large',
    [M.STATUS_UNAVAILABLE_FOR_LEGAL_REASONS] = 'Unavailable For Legal Reasons',
    [M.STATUS_INTERNAL_SERVER_ERROR] = 'Internal Server Error',
    [M.STATUS_NOT_IMPLEMENTED] = 'Not Implemented',
    [M.STATUS_BAD_GATEWAY] = 'Bad Gateway',
    [M.STATUS_SERVICE_UNAVAILABLE] = 'Service Unavailable',
    [M.STATUS_GATEWAY_TIMEOUT] = 'Gateway Timeout',
    [M.STATUS_HTTP_VERSION_NOT_SUPPORTED] = 'HTTP Version Not Supported',
    [M.STATUS_VARIANT_ALSO_NEGOTIATES] = 'Variant Also Negotiates',
    [M.STATUS_INSUFFICIENT_STORAGE] = 'Insufficient Storage',
    [M.STATUS_LOOP_DETECTED] = 'Loop Detected',
    [M.STATUS_NOT_EXTENDED] = 'Not Extended',
    [M.STATUS_NETWORK_AUTHENTICATION_REQUIRED] = 'Network Authentication Required'
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
    Jan = 1,
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

local header_name_map = {
    ['content-type'] = 'Content-Type',
    ['content-length'] = 'Content-Length',
    ['transfer-encoding'] = 'Transfer-Encoding',
    ['connection'] = 'Connection',
    ['server'] = 'Server',
    ['date'] = 'Date',
    ['etag'] = 'ETag',
    ['last-modified'] = 'Last-Modified',
    ['content-encoding'] = 'Content-Encoding',
    ['keep-alive'] = 'Keep-Alive',
    ['location'] = 'Location',
    ['if-none-match'] = 'If-None-Match',
    ['if-modified-since'] = 'If-Modified-Since'
}

local methods = {}

function methods:remote_addr()
    return self.peer
end

function methods:add_header(name, value)
    local resp = self.resp

    if resp.head_sent then
        error('http head has been sent')
    end

    resp.headers[name:lower()] = value
end

function methods:set_status(code, status)
    local resp = self.resp

    if resp.head_sent then
        error('http head has been sent')
    end

    resp.code = code

    if status then
        resp.status = status
    end

    return true
end

local function build_headers(data, headers)
    for name, value in pairs(headers) do
        local formatted_name = header_name_map[name] or name:gsub('^%l', str_upper):gsub('%-+%l', str_upper)

        data[#data + 1] = formatted_name
        data[#data + 1] = ': '
        data[#data + 1] = value
        data[#data + 1] = '\r\n'
    end
end

local function send_http_head(resp)
    if resp.head_sent then return end

    local data = resp.data

    local code = resp.code
    local status = resp.status
    local headers = resp.headers

    status = status or status_map[code]

    data[#data + 1] = 'HTTP/'
    data[#data + 1] = tostring(resp.major_version)
    data[#data + 1] = '.'
    data[#data + 1] = tostring(resp.minor_version)
    data[#data + 1] = ' '
    data[#data + 1] = tostring(code)

    if status then
        data[#data + 1] = ' '
        data[#data + 1] = status
    end

    data[#data + 1] = '\r\n'

    if not headers['content-length'] then
        headers['transfer-encoding'] = 'chunked'
    end

    build_headers(data, headers)

    data[#data + 1] = '\r\n'

    resp.head_sent = true
end

function methods:send_error(code, status, content)
    if type(code) ~= 'number' then
        error('invalid code: ' .. tostring(code))
    end

    self:set_status(code, status)
    self:add_header('connection', 'close')

    if content then
        self:send(content)
    else
        self:add_header('content-length', '0')
        send_http_head(self.resp)
    end

    return true
end

function methods:redirect(code, location)
    assert(code >= M.STATUS_MULTIPLE_CHOICES and code <= M.STATUS_PERMANENT_REDIRECT)
    self:add_header('location', location)
    return self:send_error(code)
end

function methods:send(...)
    local resp = self.resp
    local rdata = resp.data

    local args = {...}
    local nargs = #args
    local len = 0

    for i = 1, nargs do
        args[i] = tostring(args[i])
        len = len + #args[i]
    end

    if len == 0 then
        return true
    end

    if not resp.head_sent then
        send_http_head(resp)
    end

    rdata[#rdata + 1] = string.format('%x', len)
    rdata[#rdata + 1] = '\r\n'

    for i = 1, nargs do
        rdata[#rdata + 1] = args[i]
    end

    rdata[#rdata + 1] = '\r\n'

    return true
end

local function http_send_file(self, path, size, count, offset)
    local resp = self.resp
    local sock = self.sock

    if not resp.head_sent then
        send_http_head(resp)
    end

    local ok, err = self:flush()
    if not ok then
        return false, err
    end

    if offset and offset > -1 then
        size = size - offset
    end

    count = count or size

    if count > size then
        count = size
    end

    local header = string.format('%x\r\n', count)
    _, err = sock:send(header)
    if err then
        return nil, err
    end

    local ret

    ret, err = sock:sendfile(path, count, offset)
    if not ret then
        return nil, err
    end

    _, err = sock:send('\r\n')
    if err then
        return nil, err
    end

    return true
end

function methods:send_file(path, count, offset)
    local st, err = file.stat(path)
    if not st then
        return false, err
    end

    if st.type ~= 'REG' then
        return false, 'forbidden'
    end

    return http_send_file(self, path, st.size, count, offset)
end

function methods:flush()
    local resp = self.resp
    local sock = self.sock
    local data = resp.data

    if not resp.head_sent then
        send_http_head(resp)
    end

    if #data == 0 then
        return true
    end

    local _, err = sock:send(concat(data))
    if err then
        return false, err
    end

    for i = 1, #data do
        data[i] = nil
    end

    return true
end

function methods:read_body(count, timeout)
    local body_remain = self.body_remain
    local sock = self.sock

    if body_remain == 0 then
        return ''
    end

    count = count or body_remain
    if count > body_remain then
        count = body_remain
    end

    local data, err = sock:readfull(count, timeout)
    if not data then
        return nil, err
    end

    self.body_remain = body_remain - count

    return data
end

function methods:read_formdata(req, timeout)
    local sock = self.sock

    local form = req.form

    if not form.boundary then
        if req.method ~= 'POST' then
            return nil, 'not allowed method'
        end

        local content_type = req.headers['content-type'] or ''
        local boundary = content_type:match('multipart/form%-data; *boundary=(----[%w%p]+)')
        if not boundary then
            return nil, 'bad request'
        end

        form.boundary = '--' .. boundary
        form.state = 'init'

        self.formed = true
    end

    if form.state == 'init' then
        local line, err = sock:recv('l', timeout)
        if not line then
            return nil, err
        end

        if line ~= form.boundary .. '\r' then
            return nil, 'bad request'
        end

        form.boundary = '\r\n' .. form.boundary

        form.state = 'header'
    end

    if form.state == 'header' then
        local line, err = sock:recv('l', timeout)
        if not line then
            return nil, err
        end

        if line == '\r' then
            form.state = 'body'
        else
            local name, value = line:match('([%w%p]+) *: *(.+)\r?$')
            if not name or not value then
                return nil, 'invalid http header'
            end

            return 'header', { name:lower(), value }
        end
    end

    if form.state == 'body' then
        local data, found = sock:readuntil(form.boundary, timeout)
        if not data then
            return nil, found
        end

        if found then
            local x, err = sock:peek(2)
            if not x then
                return nil, err
            end

            if x == '--' then
                form.state = 'end'
            else
                if x ~= '\r\n' then
                    return nil, 'bad request'
                end

                sock:recv(2)

                form.state = 'header'
            end
        end

        return 'body', { data, found }
    end

    return 'end'
end

function methods:discard_body()
    local ok, err = self.sock:discard(self.body_remain)
    if not ok then
        return nil, err
    end

    self.body_remain = 0

    return true
end

function methods:serve_file(req)
    local options = self.options
    local path = req.path

    if path == '/' then
        path = '/' .. options.index
    end

    local phy_path = options.docroot .. path
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
            return self:send_error(M.STATUS_NOT_FOUND)
        end

        if not file.access(phy_path, 'r') then
            return self:send_error(M.STATUS_FORBIDDEN)
        end
    end

    local st, err = file.stat(phy_path)
    if not st then
        return self:send_error(M.STATUS_INTERNAL_SERVER_ERROR, nil, string.format('stat "%s" fail: %s', phy_path, err))
    end

    if st.type ~= 'REG' then
        return self:send_error(M.STATUS_FORBIDDEN)
    end

    if req.method ~= 'GET' and req.method ~= 'HEAD' then
        return self:send_error(M.STATUS_METHOD_NOT_ALLOWED)
    end

    local etag = string.format('%x-%x', st.ino, st.size)
    self:add_header('etag', etag)
    self:add_header('last-modified', os.date('%a, %d %b %Y %H:%M:%S GMT', st.mtime))

    if req.headers['if-none-match'] == etag then
        return self:set_status(M.STATUS_NOT_MODIFIED)
    end

    if req.headers['if-modified-since'] then
        local day, month, year, hour, min, sec =
            req.headers['if-modified-since']:match('^%a+, (%d%d) (%a+) (%d%d%d%d) (%d%d):(%d%d):(%d%d) GMT$')
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
                return self:set_status(M.STATUS_NOT_MODIFIED)
            end
        end
    end

    self:add_header('content-type', mime_map[suffix] or 'application/octet-stream')

    if gzip then
        self:add_header('content-encoding', 'gzip')
    end

    if req.method == 'HEAD' then
        return true
    end

    return http_send_file(self, phy_path, st.size)
end

local function handle_connection(con, handler)
    local sock = con.sock
    local peer = con.peer

    local log_prefix = peer.ipaddr .. ':' .. peer.port .. ': '
    local http_keepalive = con.options.http_keepalive
    local read_timeout = 3.0

    local method, raw_path, major_version, minor_version

    while true do
        local data, err = sock:recv('l', http_keepalive > 0 and http_keepalive or read_timeout)
        if not data then
            if err ~= 'timeout' then
                log.err(log_prefix .. err)
            end
            return false
        end

        if #data > 0 then
            method, raw_path, major_version, minor_version = data:match('^(%u+) +([%w%p]+) +HTTP/(%d+)%.(%d+)\r?$')
            if not method or not raw_path or not major_version or not minor_version then
                log.err(log_prefix .. 'not a vaild http request start line')
                return false
            end

            major_version = tonumber(major_version)
            minor_version = tonumber(minor_version)

            break
        end

        --ignore any empty line(s) received where a Request-Line is expected.
    end

    local headers = {}

    while true do
        local data, err = sock:recv('l', read_timeout)
        if not data then
            log.err(log_prefix .. 'not a complete http request: ' .. err)
            return false
        end

        if data == '\r' or data == '' then
            break
        end

        local name, value = data:match('([%w%p]+) *: *(.+)\r?$')
        if not name or not value then
            log.err(log_prefix .. 'not a vaild http header: ' .. data)
            return false
        end

        headers[str_lower(name)] = value
    end

    if str_lower(headers['transfer-encoding'] or '') == 'chunked' then
        log.err(log_prefix .. 'not support chunked http request')
        return false
    end

    local query_string = ''
    local path = raw_path

    local qpos = raw_path:find('?')
    if qpos then
        path = raw_path:sub(1, qpos - 1)
        query_string = raw_path:sub(qpos + 1)
    end

    local query = {}

    if query_string ~= '' then
        for q in query_string:gmatch('[^&]+') do
            local name, value = q:match('(.+)=(.+)')
            if name then
                query[name] = url.unescape(value)
            end
        end
    end

    con.body_remain = tonumber(headers['content-length'] or 0)

    local resp = {
        major_version = major_version,
        minor_version = minor_version,
        code = 200,
        headers = {
            server = 'Lua-eco/' .. eco.VERSION,
            date = os.date('!%a, %d %b %Y %H:%M:%S GMT')
        },
        data = {}
    }

    if http_keepalive > 0 then
        resp.headers['keep-alive'] = 'timeout=' .. tostring(http_keepalive)
    end

    con.resp = resp

    local req = {
        method = method,
        raw_path = raw_path,
        path = url.unescape(path),
        major_version = major_version,
        minor_version = minor_version,
        headers = headers,
        query = query,
        query_string = query_string,
        form = {}
    }

    if handler(con, req) == false then
        return false
    end

    if resp.code == M.STATUS_SWITCHING_PROTOCOLS then
        return false
    end

    if not resp.head_sent then
        send_http_head(resp)
    end

    -- append chunk end
    local rdata = resp.data
    rdata[#rdata + 1] = '0\r\n'
    rdata[#rdata + 1] = '\r\n'

    local ok, err = con:flush()
    if not ok then
        log.err(log_prefix .. 'flush data: ' .. err)
        return false
    end

    log.debug(log_prefix .. string.format('"%s %s HTTP/%d.%d" %d',
        method, path, major_version, minor_version, resp.code))

    local req_connection = str_lower(req.headers['connection'] or '')
    local resp_connection = str_lower(resp.headers['connection'] or '')

    if http_keepalive < 1 or (major_version == 1 and minor_version == 0)
        or req_connection == 'close'
        or req_connection == 'upgrade'
        or resp_connection == 'close'
        or con.formed
    then
        return false
    else
        ok, err = con:discard_body()
        if not ok then
            log.err(log_prefix .. 'discard body: ' .. err)
            return false
        end
    end

    return true
end

local metatable = { __index = methods }

function M.listen(ipaddr, port, options, handler)
    options = options or {}

    options.docroot = options.docroot or '.'

    if options.docroot ~= '/' then
        options.docroot = options.docroot:gsub('/$', '')
    end

    options.index = options.index or 'index.html'
    options.http_keepalive = options.http_keepalive or 30

    local sock, err

    if options.cert and options.key then
        local ssl = require 'eco.ssl'
        options.ssl = true
        sock, err = ssl.listen(ipaddr, port, options)
    else
        sock, err = socket.listen_tcp(ipaddr, port, options)
    end

    if not sock then
        return nil, err
    end

    log.debug('listen on:', ipaddr, port, options.ssl and 'ssl' or '')

    while true do
        local c, peer = sock:accept()
        if c then
            log.debug(peer.ipaddr .. ':' .. peer.port .. ': new connection')

            local con = setmetatable({
                sock = c,
                resp = {
                    code = 200,
                    headers = {
                        server = 'Lua-eco/' .. eco.VERSION
                    },
                    data = {}
                },
                peer = peer,
                options = options
            }, metatable)

            eco.run(function()
                while true do
                    if not handle_connection(con, handler) then
                        c:close()
                        break
                    end
                end
            end)
        else
            return nil, peer
        end
    end
end

return M
