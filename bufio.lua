-- SPDX-License-Identifier: MIT
-- Author: Jianhui Zhao <zhaojh329@gmail.com>

local eco = require 'eco'

--- Buffered reader utilities.
--
-- This module wraps an `eco.reader(fd)` (or any reader-like object that
-- implements `read2b(buffer, max, timeout)`) with an internal buffer, and
-- provides convenient read helpers.
--
-- All methods return `nil, 'eof'` once end-of-stream is reached.
--
-- @module eco.bufio

local M = {}

--- Buffered reader object returned by @{eco.bufio.new}.
--
-- @type bufio
local methods = {}

local function mark_eof(self, err)
    if err == 'eof' then
        self.eof = true
    end
end

--- Read all remaining data until EOF.
--
-- This reads from the underlying reader until it returns EOF, then returns all
-- buffered data.
--
-- @function bufio:readall
-- @tparam[opt] number timeout Timeout in seconds.
-- @treturn string Remaining data.
-- @treturn[2] nil On timeout or error.
-- @treturn[2] string Error message (including `'eof'`).
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

--- Read a line.
--
-- Reads until a newline (`'\n'`) is seen.
--
-- @function bufio:readline
-- @tparam[opt] number timeout Timeout in seconds.
-- @tparam[opt=false] boolean skip When true, strips the trailing newline.
-- @treturn string Line data.
-- @treturn[2] nil On timeout, EOF, or error.
-- @treturn[2] string Error message.
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

--- Read using a pattern.
--
-- Supported patterns:
--
-- - `'a'` or `'*a'`: read all remaining data (same as @{bufio:readall})
-- - `'l'` or `'*l'`: read a line without newline (same as @{bufio:readline} with skip=true)
-- - `'L'` or `'*L'`: read a line with newline (if present)
-- - `integer`: read exactly that many bytes (may block until enough data)
--
-- @function bufio:read
-- @tparam string|int pattern Read pattern.
-- @tparam[opt] number timeout Timeout in seconds.
-- @treturn string|number data
-- @treturn[2] nil On timeout, EOF, or error.
-- @treturn[2] string Error message.
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

local function readfull_large(self, total, timeout)
    local rd = self.rd
    local b = self.b

    local remaining = total
    local size = b:size()
    local chunks = {}

    local len = b:len()
    if len > 0 then
        chunks[#chunks + 1] = b:pull()
        remaining = remaining - len
    end

    while remaining > 0 do
        local n, err = rd:read2b(b, -1, timeout)
        if not n then
            mark_eof(self, err)
            return nil, err
        end

        len = b:len()

        -- Pull only when we either have enough bytes to finish, or the buffer is full.
        -- This reduces chunk count while avoiding "buffer is full" errors.
        if len >= remaining or len == size then
            local take = remaining
            if take > len then
                take = len
            end

            chunks[#chunks + 1] = b:pull(take)
            remaining = remaining - take
        end
    end

    return table.concat(chunks)
end

--- Read exactly `total` bytes.
--
-- Unlike @{bufio:read} with an integer pattern, this function documents the
-- intent explicitly and always reads exactly `total` bytes or returns an error.
--
-- @function bufio:readfull
-- @tparam int total Total bytes to read.
-- @tparam[opt] number timeout Timeout in seconds.
-- @treturn string data
-- @treturn[2] nil On timeout, EOF, or error.
-- @treturn[2] string Error message.
function methods:readfull(total, timeout)
    assert(math.type(total) == 'integer')

    if self.eof then
        return nil, 'eof'
    end

    local rd = self.rd
    local b = self.b

    if total > b:size() then
        return readfull_large(self, total, timeout)
    end

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

--- Read until the specified `needle` is found.
--
-- This function can be called multiple times. It returns data as it arrives.
-- When `needle` is seen, it returns the data preceding it and a boolean `true`.
-- The `needle` itself is consumed and not included in returned data.
--
-- When `needle` is not yet seen, it may return a partial chunk and `nil` as the
-- second return value.
--
-- @function bufio:readuntil
-- @tparam string needle Non-empty delimiter.
-- @tparam[opt] number timeout Timeout in seconds.
-- @treturn string Data chunk.
-- @treturn[opt] boolean true when delimiter is found.
-- @treturn[2] nil On timeout, EOF, or error.
-- @treturn[2] string Error message.
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

--- Peek the next `len` bytes without consuming them.
--
-- @function bufio:peek
-- @tparam int len Bytes to peek.
-- @tparam[opt] number timeout Timeout in seconds.
-- @treturn string data
-- @treturn[2] nil On timeout, EOF, or error.
-- @treturn[2] string Error message.
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

--- Discard `len` bytes.
--
-- @function bufio:discard
-- @tparam int len Bytes to discard.
-- @tparam[opt] number timeout Timeout in seconds.
-- @treturn boolean true On success.
-- @treturn[2] nil On timeout, EOF, or error.
-- @treturn[2] string Error message.
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

--- End of `bufio` class section.
-- @section end

local metatable = {
    __index = methods
}

--- Create a buffered reader.
--
-- `src` can be:
--
-- - an integer file descriptor, or
-- - a reader-like object that provides `read2b(buffer, max, timeout)`.
--
-- @function new
-- @tparam int|table|userdata src File descriptor or reader-like object.
-- @tparam[opt] int size Initial buffer size (passed to @{eco.buffer}).
-- @treturn bufio Buffered reader.
-- @usage
-- local b = bufio.new(0) -- stdin
-- local line = assert(b:read('l'))
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
