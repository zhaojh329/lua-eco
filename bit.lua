-- SPDX-License-Identifier: MIT
-- Author: Jianhui Zhao <zhaojh329@gmail.com>

local bit

if tonumber(_VERSION:match('%d%.%d')) < 5.3 then
    bit = require 'bit'
else
    bit = load([[
        local M = {}

        function M.band(...)
            local r
            for _, v in ipairs({...}) do
                r = r and r & v or v
            end
            return r
        end

        function M.bor(...)
            local r
            for _, v in ipairs({...}) do
                r = r and r | v or v
            end
            return r
        end

        function M.bxor(a, b)
            return a ~ b
        end

        function M.rshift(x, n)
            return x >> n
        end

        function M.lshift(x, n)
            return x << n
        end

        function M.bnot(x)
            return ~x
        end

        return M
    ]])()
end

return bit
