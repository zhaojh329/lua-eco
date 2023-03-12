-- SPDX-License-Identifier: MIT
-- Author: Jianhui Zhao <zhaojh329@gmail.com>

local M = {}

local tonumber = tonumber

function M.escape(s)
    return (string.gsub(s, "([^A-Za-z0-9_])", function(c)
        return string.format("%%%02x", string.byte(c))
    end))
end

function M.unescape(s)
    return (string.gsub(s, "%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end))
end

-- <scheme>://<user>:<password>@<host>:<port>/<path>;<params>?<query>#<frag>
function M.parse(url)
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

return M
