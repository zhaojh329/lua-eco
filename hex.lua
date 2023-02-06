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

-- returns the hexadecimal encoding of src
function M.encode(bin)
    local s = bin:gsub('.', function(c)
        return string.format('%02x', c:byte(1))
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
