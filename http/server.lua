-- SPDX-License-Identifier: MIT
-- Author: Jianhui Zhao <zhaojh329@gmail.com>

local socket = require 'eco.socket'
local url = require 'eco.http.url'
local file = require 'eco.file'
local ssl = require 'eco.ssl'
local log = require 'eco.log'

local str_lower = string.lower
local concat = table.concat
local tonumber = tonumber

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

local methods = {}

function methods:closed()
    return getmetatable(self).sock:closed()
end

function methods:remote_addr()
    return getmetatable(self).peer
end

function methods:add_header(name, value)
    local resp = getmetatable(self).resp

    if resp.head_sent then
        error('http head has been sent')
    end

    resp.headers[name:lower()] = value
end

function methods:set_status(code, status)
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

local function build_headers(data, headers)
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

local function send_http_head(resp)
    if resp.head_sent then return end

    local data = resp.data

    local code = resp.code
    local status = resp.status

    status = status or status_map[code]

    data[#data + 1] = string.format('HTTP/%d.%d %d', resp.major_version, resp.minor_version, code)

    if status then
        data[#data + 1] = ' ' .. status
    end

    data[#data + 1] = '\r\n'

    build_headers(data, resp.headers)

    data[#data + 1] = '\r\n'

    resp.head_sent = true
end

function methods:send_error(code, status, content)
    local mt = getmetatable(self)

    if mt.sock:closed() then
        return false, 'closed'
    end

    if type(code) ~= 'number' then
        error('invalid code: ' .. tostring(code))
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

function methods:send(...)
    local mt = getmetatable(self)
    local resp = mt.resp

    if mt.sock:closed() then
        return false, 'closed'
    end

    local data = concat({...})
    local len = #data
    if len == 0 then
        return true
    end

    if not resp.head_sent then
        send_http_head(resp)
    end

    local rdata = resp.data

    rdata[#rdata + 1] = string.format('%x\r\n', len)
    rdata[#rdata + 1] = data
    rdata[#rdata + 1] = '\r\n'

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

    _, err = sock:sendfile(fd, count, offset)
    if err then
        return false, err
    end

    _, err = sock:send('\r\n')
    if err then
        return false, err
    end

    return true
end

function methods:send_file_fd(fd, size, count, offset)
    local mt = getmetatable(self)
    local resp = mt.resp
    local sock = mt.sock

    if count and count < 1 then
        return true
    end

    if not resp.head_sent then
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

    return true
end

function methods:send_file(path, count, offset)
    local mt = getmetatable(self)

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

    _, err = self:send_file_fd(fd, st.size, count, offset)
    file.close(fd)

    if err then
        return false, err
    end

    return true
end

function methods:flush()
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

    local _, err = sock:send(concat(data))
    if err then
        sock:close()
        return false, err
    end

    resp.data = {}

    return true
end

function methods:read_body(count, timeout)
    local mt = getmetatable(self)
    local body_remain = mt.body_remain
    local sock = mt.sock

    if sock:closed() then
        return nil, 'closed'
    end

    if body_remain == 0 then
        return nil
    end

    timeout = timeout or 3.0

    count = count or body_remain
    if count > body_remain then
        count = body_remain
    end

    if count < 1 then
        return ''
    end

    local data, err, partial = sock:recvfull(count, timeout)
    if not data then
        sock:close()

        if partial then
            return nil, err, partial
        end
        return nil, err
    end

    mt.body_remain = mt.body_remain - #data

    return data
end

function methods:discard_body()
    local mt = getmetatable(self)
    local sock = mt.sock

    local _, err = sock:discard(mt.body_remain, 3.0)
    if err then
        sock:close()
        return false, err
    end

    return true
end

function methods:serve_file(req)
    local mt = getmetatable(self)
    local options = mt.options
    local path = req.path

    if mt.sock:closed() then
        return false, 'closed'
    end

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

    local fd, err = file.open(phy_path)
    if not fd then
        return self:send_error(M.STATUS_INTERNAL_SERVER_ERROR, nil, string.format('open "%s" fail: %s', phy_path, err))
    end

    _, err = self:send_file_fd(fd, st.size)
    file.close(fd)

    if err then
        return false, err
    end

    return true
end

local function handle_connection(con, handler)
    local mt = getmetatable(con)
    local sock = mt.sock
    local peer = mt.peer

    local log_prefix = peer.ipaddr .. ':' .. peer.port .. ': '
    local http_keepalive = mt.options.http_keepalive
    local read_timeout = 3.0

    local method, path, major_version, minor_version

    while true do
        local data, err = sock:recv('*l', http_keepalive > 0 and http_keepalive or read_timeout)
        if not data then
            if err == 'closed' then
                log.debug(log_prefix .. err)
            else
                log.err(log_prefix .. err)
            end
            return false
        end

        if #data > 0 then
            method, path, major_version, minor_version = data:match('^(%u+)%s+(%S+)%s+HTTP/(%d+)%.(%d+)$')
            if not method or not path or not major_version or not minor_version then
                log.err(log_prefix .. 'not a vaild http request start line')
                return false
            end

            if not method then
                log.err(log_prefix .. 'not supported http method "' .. method .. '"')
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
        local data, err = sock:recv('*l', read_timeout)
        if not data then
            log.err(log_prefix .. 'not a complete http request: ' .. err)
            return false
        end

        if data == '' then
            break
        end

        local name, value = data:match('^([%w-_]+):%s*(.+)$')
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

    path = path:gsub('%?(.*)', function(s)
        query_string = s
        return ''
    end)

    local query = {}

    for q in query_string:gmatch('[^&]+') do
        local name, value = q:match('(.+)=(.+)')
        if name then
            query[name] = url.unescape(value)
        end
    end

    mt.body_remain = tonumber(headers['content-length'] or 0)

    local resp = {
        major_version = major_version,
        minor_version = minor_version,
        code = 200,
        headers = {
            server = 'Lua-eco/' .. eco.VERSION,
            date = os.date('!%a, %d %b %Y %H:%M:%S GMT'),
            ['transfer-encoding'] = 'chunked'
        },
        data = {}
    }

    if http_keepalive > 0 then
        resp.headers['keep-alive'] = string.format('timeout=%d', http_keepalive)
    end

    mt.resp = resp

    local req = {
        method = method,
        path = url.unescape(path),
        major_version = major_version,
        minor_version = minor_version,
        headers = headers,
        query = query
    }

    handler(con, req)

    if sock:closed() then
        log.err(log_prefix .. 'closed')
        return false
    end

    if resp.code == M.STATUS_SWITCHING_PROTOCOLS then
        return false
    end

    if not resp.head_sent then
        send_http_head(resp)
    end

    -- append chunk end
    local data = resp.data
    data[#data + 1] = '0\r\n'
    data[#data + 1] = '\r\n'

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
    then
        sock:close()
    else
        ok, err = con:discard_body()
        if not ok then
            log.err(log_prefix .. 'discard body: ' .. err)
            return false
        end
    end

    return true
end

local function set_socket_options(sock, options)
    if options.ssl then
        sock = sock:socket()
    end

    if options.tcp_nodelay then
        sock:setoption('tcp_nodelay', true)
    end

    local tcp_keepalive = options.tcp_keepalive or 0
    if tcp_keepalive > 0 then
        sock:setoption('keepalive', true)
        sock:setoption('tcp_keepidle', 1)
        sock:setoption('tcp_keepcnt', 3)
        sock:setoption('tcp_keepintvl', tcp_keepalive)
        sock:setoption('tcp_fastopen', 5)
    end
end

function M.listen(ipaddr, port, options, handler)
    options = options or {}

    options.docroot = options.docroot or '.'

    if options.docroot ~= '/' then
        options.docroot = options.docroot:gsub('/$', '')
    end

    options.index = options.index or 'index.html'
    options.http_keepalive = options.http_keepalive or 30

    local sock, err, listen

    if options.cert and options.key then
        options.ssl = true
        if options.ipv6 then
            options.ipv6_v6only = true
            listen = ssl.listen6
        else
            listen = ssl.listen
        end
    else
        if options.ipv6 then
            options.ipv6_v6only = true
            listen = socket.listen_tcp6
        else
            listen = socket.listen_tcp
        end
    end

    sock, err = listen(ipaddr, port, options)
    if not sock then
        return nil, err
    end

    set_socket_options(sock, options)

    while true do
        local c, peer = sock:accept()
        if c then
            log.debug(peer.ipaddr .. ':' .. peer.port .. ': new connection')

            eco.run(function(c)
                local con = setmetatable({}, {
                    sock = c,
                    resp = {
                        code = 200,
                        headers = {
                            server = 'Lua-eco/' .. eco.VERSION
                        }
                    },
                    peer = peer,
                    options = options,
                    __index = methods
                })

                while not c:closed() do
                    if not handle_connection(con, handler) then
                        c:close()
                    end
                end
            end, c)
        else
            log.err('accept fail: ' .. peer)
        end
    end
end

return M
