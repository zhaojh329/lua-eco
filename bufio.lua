-- SPDX-License-Identifier: MIT
-- Author: Jianhui Zhao <zhaojh329@gmail.com>

local eco = require 'eco'

local M = {}

local methods = {}

local function mark_eof(self, err)
    if err == 'eof' then
        self.eof = true
    end
end

-- reads the whole file or reads from socket until the connection closed.
function methods:readall(timeout)
    if self.eof then
        return nil, 'eof'
    end

    local rd = self.rd
    local b = self.b

    while true do
        local n, err = rd:read2b(b, -1, timeout)
        if not n then
            if err == 'eof' then
                self.eof = true
                break
            end
            return nil, err
        end
    end

    return b:pull()
end

-- reads the next line
function methods:readline(timeout, skip)
    if self.eof then
        return nil, 'eof'
    end

    local rd = self.rd
    local b = self.b

    local start = 0

    while true do
        local pos = b:index(start, '\n')
        if pos then
            if not skip then
                pos = pos + 1
            end

            local line = b:pull(pos)

            if skip then
                b:discard(1)
            end

            return line
        end

        start = b:len()

        local n, err = rd:read2b(b, -1, timeout)
        if not n then
            mark_eof(self, err)
            return nil, err
        end
    end
end

--[[
  Reads according to the given pattern, which specify what to read.

  In case of success, it returns the data received; in case of error, it returns
  nil with a string describing the error.

  The available pattern are:
    'a': reads the whole file or reads from socket until the connection closed.
    'l': reads the next line skipping the end of line character.
    'L': reads the next line keeping the end-of-line character (if present).
    integer: reads a string with up to this integer of bytes.
--]]
function methods:read(pattern, timeout)
    if self.eof then
        return nil, 'eof'
    end

    if math.type(pattern) == 'integer' then
        local b = self.b

        while b:len() < pattern do
            local n, err = self.rd:read2b(b, -1, timeout)
            if not n then
                mark_eof(self, err)
                return nil, err
            end
        end

        return b:pull(pattern)
    end

    if type(pattern) ~= 'string' then
        error('bad argument #1 (invalid format)')
    end

    if pattern:sub(1, 1) == '*' then
        pattern = pattern:sub(2)
    end

    if pattern == 'a' then
        return self:readall(timeout)
    end

    if pattern == 'l' or pattern == 'L' then
        return self:readline(timeout, pattern == 'l')
    end

    error('bad argument #1')
end

-- Reads until it reads exactly desired size of data or an error occurs
function methods:readfull(total, timeout)
    assert(math.type(total) == 'integer')

    if self.eof then
        return nil, 'eof'
    end

    local rd = self.rd
    local b = self.b

    local len = b:len()

    while len < total do
        local n, err = rd:read2b(b, -1, timeout)
        if not n then
            mark_eof(self, err)
            return nil, err
        end

        len = len + n
    end

    return b:pull(total)
end

--[[
 Read the data stream until it sees the specified needle or an error occurs.
 The function can be called multiple times.
 It returns the received data on each invocation followed a boolean `true` if
 the specified needle occurs.
--]]
function methods:readuntil(needle, timeout)
    assert(type(needle) == 'string' and #needle > 0)

    if self.eof then
        return nil, 'eof'
    end

    local rd = self.rd
    local b = self.b

    while true do
        local pos = b:find(0, needle)
        if pos then
            local data = b:pull(pos)
            b:discard(#needle)
            return data, true
        end

        local len = b:len()
        if len > #needle then
            return b:pull(len - #needle + 1)
        end

        local n, err = rd:read2b(b, -1, timeout)
        if not n then
            mark_eof(self, err)
            return nil, err
        end
    end
end

-- Returns the next n bytes without moving read position
function methods:peek(len, timeout)
    assert(math.type(len) == 'integer')

    if self.eof then
        return nil, 'eof'
    end

    local rd = self.rd
    local b = self.b

    while b:len() < len do
        local n, err = rd:read2b(b, -1, timeout)
        if not n then
            mark_eof(self, err)
            return nil, err
        end
    end

    return b:data(0, len)
end

function methods:discard(len, timeout)
    assert(math.type(len) == 'integer')

    if self.eof then
        return nil, 'eof'
    end

    local rd = self.rd
    local b = self.b

    while len > 0 do
        len = len - b:discard(len)

        if len == 0 then
            return true
        end

        local n, err = rd:read2b(b, -1, timeout)
        if not n then
            mark_eof(self, err)
            return nil, err
        end
    end

    return true
end

local metatable = {
    __index = methods
}

function M.new(src, size)
    local rd

    if math.type(src) == 'integer' then
        rd = eco.reader(src)
    elseif type(src) == 'userdata' or type(src) == 'table' then
        if type(src.read2b) == 'function' then
            rd = src
        end
    end

    if not rd then
        return error('invalid argument')
    end

    local b = eco.buffer(size)

    return setmetatable({
        b = b,
        rd = rd
    }, metatable)
end

return M
