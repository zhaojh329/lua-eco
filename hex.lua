-- SPDX-License-Identifier: MIT
-- Author: Jianhui Zhao <zhaojh329@gmail.com>

--- Hex encoding/decoding utilities.
--
-- This module provides helpers to encode raw bytes into lowercase hexadecimal
-- strings, decode hex strings back into raw bytes, and format a hexdump similar
-- to `hexdump -C`.
--
-- @module eco.encoding.hex

local M = {}

--- Encode bytes to a hexadecimal string.
--
-- @function encode
-- @tparam string bin Input bytes.
-- @tparam[opt=''] string sep Optional separator inserted between bytes.
-- @treturn string Lowercase hexadecimal string.
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

--- Decode a hexadecimal string into bytes.
--
-- On malformed input, returns `nil, 'input is malformed'`.
--
-- @function decode
-- @tparam string s Hex string.
-- @treturn string out Decoded bytes.
-- @treturn[2] nil On malformed input.
-- @treturn[2] string Error message.
function M.decode(s)

    local bin, n = s:gsub('%x%x', function(c)
        return string.char(tonumber(c, 16) or 0)
    end)

    if #s ~= n * 2 then
        return nil, 'input is malformed'
    end

    return bin
end

--- Format a hexdump of the given data.
--
-- The format matches the output of `hexdump -C`.
--
-- @function dump
-- @tparam string data Input bytes.
-- @treturn string Dump string (contains newlines).
-- @usage
-- local hex = require 'eco.encoding.hex'
-- print(hex.dump('hello'))
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
