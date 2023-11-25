-- SPDX-License-Identifier: MIT
-- Author: Jianhui Zhao <zhaojh329@gmail.com>

local buffer = require 'eco.core.bufio'
local sys = require 'eco.core.sys'
local file = require 'eco.file'

local M = {}

local methods = {}

function methods:size()
    return self.b:size()
end

function methods:length()
    return self.b:length()
end

function methods:room()
    return self.b:room()
end

function methods:tail()
    return self.b:tail()
end

function methods:add(n)
    return self.b:add(n)
end

-- Set the timeout value in seconds for subsequent read operations
function methods:settimeout(seconds)
    self.timeout = seconds
end

-- Returns the next n bytes without advancing read
function methods:peek(n)
    if self.eof then
        return nil, self.eof_err
    end

    local b = self.b
    local blen = b:length()

    if blen < n then
        if n > b:size() then
            return nil, 'buffer is full'
        end

        if blen + b:room() < n then
            b:slide()
        end

        local r, err = self:fill()
        if not r then
            return nil, err
        end
    end

    return b:peek(n)
end

--[[
    Skips the next n bytes.
    If successful, returns `n`. In case of error, the method returns nil followed by
    an error message, followed a number indicate how many bytes have been discarded.
--]]
function methods:discard(n)
    if self.eof then
        return nil, self.eof_err
    end

    local b = self.b

    if n < 1 then return 0 end

    local skiped = b:skip(n)

    while skiped < n do
        local r, err = self:fill()
        if not r then
            return nil, err, skiped
        end
        skiped = skiped + b:skip(n - skiped)
    end

    return n
end

--[[
    Reads according to the given pattern, which specify what to read.

    In case of success, it returns the data received; in case of error, it returns
    nil with a string describing the error.

    The available pattern are:
        'a': reads the whole file or until the connection is closed.
        'l': reads the next line skipping the end of line character.
        'L': reads the next line keeping the end-of-line character (if present).
        number: reads a string with up to this number of bytes.
--]]
function methods:read(pattern)
    if self.eof then
        return nil, self.eof_err
    end

    local b = self.b

    if type(pattern) == 'number' then
        assert(pattern > 0)

        if b:length() == 0 then
            local r, err = self:fill()
            if not r then
                return nil, err
            end
        end

        return b:read(pattern)
    end

    assert(type(pattern) == 'string')

    -- skip optional '*' (for compatibility)
    if pattern:sub(1, 1) == '*' then
        pattern = pattern:sub(2)
    end

    if pattern == 'a' then
        local data = {}

        while true do
            data[#data+1] = b:read()

            local r, err = self:fill()
            if not r then
                if self.eof then break end
                return nil, err
            end
        end

        return table.concat(data)
    end

    assert(pattern == 'l' or pattern == 'L')

    local keep = pattern == 'L'
    local data = {}

    while true do
        local idx = b:index(0x0a) -- '\n'
        if idx then
            data[#data + 1] = b:read(idx)

            if keep then
                data[#data + 1] = b:read(1)
            else
                b:skip(1)
            end

            break
        end

        if b:room() == 0 then
            data[#data + 1] = b:read()
        end

        local r, err = self:fill()
        if not r then
            if self.eof then
                data[#data + 1] = b:read()
                break
            end
            return nil, err
        end
    end

    return table.concat(data)
end

-- Reads exactly n bytes. Returns nil followed by an error message if fewer bytes were read.
function methods:readfull(n)
    if self.eof then
        return nil, self.eof_err
    end

    local b = self.b
    local blen = b:length()

    if blen >= n then
        return b:read(n)
    end

    local data = {}

    while true do
        local chunk = b:read(n)

        data[#data + 1] = chunk
        n = n - #chunk

        if n == 0 then break end

        local r, err = self:fill()
        if not r then
            return nil, err
        end
    end

    return table.concat(data)
end

--[[
    Read the data stream until it sees the specified pattern or an error occurs.
    The function can be called multiple times.
    It returns the received data on each invocation followed a boolean `true` if the specified pattern occurs.
--]]
function methods:readuntil(pattern)
    if self.eof then
        return nil, self.eof_err
    end

    local pattern_len = #pattern
    local b = self.b

    while true do
        local idx = b:find(pattern)
        if idx then
            local data = b:read(idx)
            b:skip(pattern_len)
            return data, true
        end

        local blen = b:length()
        if blen > pattern_len then
            return b:read(blen - pattern_len + 1)
        end

        b:slide()

        local r, err = self:fill()
        if not r then
            return nil, err
        end
    end
end

local metatable = { __index = methods }

local function create_default_fill(fd)
    local w = eco.watcher(eco.IO, fd)

    local st, err = file.fstat(fd)
    if not st then
        return nil, err
    end

    local eof_err = st['type'] == 'SOCK' and 'closed' or 'eof'

    return function(self)
        if self.eof then return nil, eof_err end

        if not w:wait(self.timeout) then
            return nil, 'timeout'
        end

        local r, err = self.b:fill(fd)
        if not r then
            return nil, sys.strerror(err)
        end

        if r == 0 then
            self.eof = true
            self.eof_err = eof_err
            return nil, eof_err
        end

        return r
    end
end

function M.new(source, size)
    local fill, err

    if type(source) == 'function' then
        fill = source
    elseif type(source) == 'number' then
        fill, err = create_default_fill(source)
        if not fill then
            return nil, err
        end
    else
        error('invalid source')
    end

    local b = buffer.new(size)

    return setmetatable({
        b = b,
        eof = false,
        fill = fill
    }, metatable)
end

return M
