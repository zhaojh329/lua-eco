-- SPDX-License-Identifier: MIT
-- Author: Jianhui Zhao <zhaojh329@gmail.com>

local file = require 'eco.core.file'
local sys = require 'eco.core.sys'
local time = require 'eco.time'

local M = {}

function M.readfile(path, m)
    local f, err = io.open(path, 'r')
    if not f then
        return nil, err
    end

    local data, err = f:read(m or '*a')
    f:close()

    if not data then
        return nil, err
    end

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

    if not n then
        return nil, err
    end
    return n
end

function M.flock(fd, operation, timeout)
    local deadtime

    if timeout then
        deadtime = sys.uptime() + timeout
    end

    while true do
        local ok, errno = file.flock(fd, operation)
        if ok then
            return true
        end

        if errno ~= sys.EAGAIN then
            return false, sys.strerror(errno)
        end

        if deadtime and sys.uptime() > deadtime then
            return false, 'timeout'
        end

        time.sleep(0.001)
    end
end

function M.sync()
    local pid, err = sys.exec('sync')
    if not pid then
        return nil, err
    end

    eco.watcher(eco.CHILD, pid):wait()

    return true
end

return setmetatable(M, { __index = file })
