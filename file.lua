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

local file = require 'eco.core.file'

local M = {}

function M.readfile(path, m)
    local f, err = io.open(path, 'r')
    if not f then
        return nil, err
    end

    local data = f:read(m or '*a')
    f:close()

    return data
end

function M.writefile(path, data, append)
    local m = 'w'

    if append then
        m = 'a'
    end

    local f, err = io.open(path, m)
    if not f then
        return nil, err
    end

    local n, err = f:write(data)
    f:close()

    return n, err
end

function M.read(fd, n, timeout)
    local w, err = eco.watcher(eco.IO, fd)
    if not w then
        return nil, err
    end

    if not w:wait(timeout) then
        return nil, 'timeout'
    end

    return file.read(fd, n)
end

function M.write(fd, data)
    local w, err = eco.watcher(eco.IO, fd, eco.WRITE)
    if not w then
        return nil, err
    end

    w:wait()

    return file.write(fd, data)
end

return setmetatable(M, { __index = file })
