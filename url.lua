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

local M = {}

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
