-- SPDX-License-Identifier: MIT
-- Author: Jianhui Zhao <zhaojh329@gmail.com>

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
    if n <= 0 then return '' end

    local w, err = eco.watcher(eco.IO, fd)
    if not w then
        return nil, err
    end

    if not w:wait(timeout) then
        return nil, 'timeout'
    end

    return file.read(fd, n)
end

function M.read_to_buffer(fd, b, timeout)
    if b:room() == 0 then
        return nil, 'buffer is full'
    end

    local w, err = eco.watcher(eco.IO, fd)
    if not w then
        return nil, err
    end

    if not w:wait(timeout) then
        return nil, 'timeout'
    end

    return file.read_to_buffer(fd, b)
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
