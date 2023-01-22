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

local buffer = require 'eco.core.buffer'
local time = require 'eco.time'

local M = {}

local methods = {}

function methods:read(n, timeout)
    local mt = getmetatable(self)
    local b = mt.b
    local blen = b:length()

    if blen == 0 then
        local _, err = mt.reader(b, timeout)
        if err then
            return nil, err
        end
    end

    blen = b:length()

    if n > blen then
        n = blen
    end

    return b:read(n)
end

function methods:readline(timeout, trim)
    local deadtime = timeout and (time.now() + timeout)
    local mt = getmetatable(self)
    local reader = mt.reader
    local b = mt.b
    local offset = 0

    while true do
        local pos = b:index('\n', offset)
        if pos > -1 then
            local data = b:read(pos + 1)

            if trim then
                local len = pos

                if data:sub(len, len) == '\r' then
                    len = len - 1
                end

                data = data:sub(1, len)
            end

            return data
        end

        offset = b:length()

        local _, err = reader(b, deadtime and (deadtime - time.now()))
        if err then
            return nil, err, b:read()
        end
    end
end

function M.new(reader, size)
    return setmetatable({}, {
        b = buffer.new(size),
        reader = reader,
        __index = methods
    })
end

return M
