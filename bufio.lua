-- SPDX-License-Identifier: MIT
-- Author: Jianhui Zhao <zhaojh329@gmail.com>

local buffer = require 'eco.core.bufio'
local time = require 'eco.time'
local concat = table.concat
local str_sub = string.sub

local M = {}

local methods = {}

function methods:size()
    local mt = getmetatable(self)
    return mt.size
end

function methods:length()
    local mt = getmetatable(self)
    return mt.b:length()
end

-- Returns the next n bytes without advancing the reader
function methods:peek(n, timeout)
    local mt = getmetatable(self)
    local reader = mt.reader
    local b = mt.b
    local blen = b:length()

    if blen < n then
        if n > b:size() then
            return nil, 'buffer is full'
        end

        if blen + b:room() < n then
            b:slide()
        end

        local _, err = reader:read2b(b, timeout)
        if err then
            return nil, err, b:peek(n)
        end
    end

    return b:peek(n)
end

--[[
    Skips the next n bytes.
    If successful, returns `n`. In case of error, the method returns nil followed by
    an error message, followed a number indicate how many bytes have been discarded.
--]]
function methods:discard(n, timeout)
    local mt = getmetatable(self)
    local reader = mt.reader
    local b = mt.b

    if n < 1 then
        return 0
    end

    local skiped = b:skip(n)

    local deadtime

    if timeout then
        deadtime = time.now() + timeout
    end

    while skiped < n do
        local _, err = reader:read2b(b, deadtime and (deadtime - time.now()))
        if err then
            return nil, err, skiped
        end
        skiped = skiped + b:skip(n - skiped)
    end

    return n
end

-- Reads at most n bytes.
function methods:read(n, timeout)
    local mt = getmetatable(self)
    local reader = mt.reader
    local b = mt.b

    if n == 0 then
        return ''
    end

    if b:length() == 0 then
        if n > b:size() then
            return reader:read(n, timeout)
        end

        local _, err = reader:read2b(b, timeout)
        if err then
            return nil, err
        end
    end

    return b:read(n)
end

-- Reads exactly n bytes. Returns nil followed by
-- an error message if fewer bytes were read.
function methods:readfull(n, timeout)
    local mt = getmetatable(self)
    local reader = mt.reader
    local b = mt.b
    local blen = b:length()

    if blen >= n then
        return b:read(n)
    end

    if blen + b:room() < n then
        b:slide()
    end

    local data = {}

    local deadtime

    if timeout then
        deadtime = time.now() + timeout
    end

    local size = b:size()

    while n > 0 do
        local _, err = reader:read2b(b, deadtime and (deadtime - time.now()))
        if err then
            local chunk = b:read(n)
            data[#data + 1] = chunk

            local partial = concat(data)
            if #partial > 0 then
                return nil, err, partial
            end
            return nil, err
        end

        local blen = b:length()
        if blen == size or blen >= n then
            local chunk = b:read(n)
            data[#data + 1] = chunk
            n = n - #chunk
        end
    end

    return concat(data)
end

-- Reads a single line, not including the end-of-line bytes("\r\n" or "\n").
function methods:readline(timeout)
    local mt = getmetatable(self)
    local reader = mt.reader
    local b = mt.b

    local deadtime

    if timeout then
        deadtime = time.now() + timeout
    end

    local data = {}

    while true do
        local idx = b:index(0x0a) -- '\n'
        if idx > -1 then
            local line

            if idx > 0 then
                line = b:read(idx)
            end

            b:skip(1)

            if line then
                if str_sub(line, #line) == '\r' then
                    line = str_sub(line, 1, #line - 1)
                end

                data[#data + 1] = line
            end

            return concat(data)
        end

        if b:room() == 0 then
            data[#data + 1] = b:read()
        end

        local _, err = reader:read2b(b, deadtime and (deadtime - time.now()))
        if err then
            data[#data + 1] = b:read()
            return nil, err, concat(data)
        end
    end
end

function M.new(reader, size)
    if type(reader) ~= 'table' then
        error('"reader" must be a table')
    end

    if type(reader.read) ~= 'function' then
        error('not found "read" function in reader')
    end

    if type(reader.read2b) ~= 'function' then
        error('not found "read2b" function in reader')
    end

    local b = buffer.new(size)
    return setmetatable({}, {
        b = b,
        reader = reader,
        __index = methods
    })
end

return M
