-- SPDX-License-Identifier: MIT
-- Author: Jianhui Zhao <zhaojh329@gmail.com>

local M = {}

-- returns the hexadecimal encoding of src
function M.encode(bin, sep)
    local first = true

    sep = sep or ''

    local s = bin:gsub('.', function(c)
        if first then
            first = false
            return string.format('%02x', c:byte(1))
        else
            return string.format('%s%02x', sep, c:byte(1))
        end
    end)

    return s
end

-- returns the bytes represented by the hexadecimal string s
function M.decode(s)

    local bin, n = s:gsub('%x%x', function(c)
        return string.char(tonumber(c, 16))
    end)

    if #s ~= n * 2 then
        return nil, 'input is malformed'
    end

    return bin
end

-- Dump returns a string that contains a hex dump of the given data.
-- The format of the hex dump matches the output of `hexdump -C` on the command line.
function M.dump(data)
    local lines = {}

    for i = 1, #data, 16 do
        local nums = { data:byte(i, i + 15) }
        local line = {}

        local address = string.format('%08x ', i - 1)

        for j, n in ipairs(nums) do
            line[#line + 1] = string.format('%02x ', n)
            if j == 8 then
                line[#line + 1] = ' '
            end
        end

        for j = #nums + 1, 16 do
            if j == 8 then
                line[#line + 1] = ' '
            end
            line[#line + 1] = '   '
        end

        line[#line + 1] = ' |'

        line[#line + 1] = data:sub(i, i + 15):gsub('[%c%z]', '.')
        line[#line + 1] = '\n'
        lines[#lines + 1] = address
        lines[#lines + 1] = table.concat(line)
    end

    return table.concat(lines)
end

return M
