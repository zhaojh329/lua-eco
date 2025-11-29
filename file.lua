-- SPDX-License-Identifier: MIT
-- Author: Jianhui Zhao <zhaojh329@gmail.com>

local file = require 'eco.internal.file'
local time = require 'eco.time'
local sys = require 'eco.sys'
local eco = require 'eco'

local M = {
    SKIP = 1
}

function M.readfile(path, m)
    local f<close>, err = io.open(path, 'r')
    if not f then
        return nil, err
    end

    return f:read(m or '*a')
end

function M.writefile(path, data, append)
    local m = 'w'

    if append then
        m = 'a'
    end

    local f<close>, err = io.open(path, m)
    if not f then
        return nil, err
    end

    _, err = f:write(data)
    if err then
        return nil, err
    end

    return true
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

        time.sleep(0.1)
    end
end

function M.sync(timeout)
    local p<close>, err = sys.exec('sync')
    if not p then
        return nil, err
    end

    return p:wait(timeout)
end

local inotify_methods = {}

local function read_inotify_event(self, timeout)
    local data = self.data
    local wd, mask, _, len = string.unpack('I4I4I4I4', data)
    local name

    if len > 0 then
        name = data:sub(16, len + 16):gsub('\0+', '')
    end

    data = data:sub(len + 17)

    if #data > 0 then
        self.data = data
    else
        self.data = nil
    end

    local path = self.watchs[wd]
    if not path then
        return self:wait(timeout)
    end

    if len > 0 then
        if path:sub(#path) ~= '/' then
            path = path .. '/'
        end

        name = path .. name
    else
        name = path
    end

    local event

    if mask & file.IN_ACCESS > 0 then
        event = 'ACCESS'
    elseif mask & file.IN_MODIFY > 0 then
        event = 'MODIFY'
    elseif mask & file.IN_ATTRIB > 0 then
        event = 'ATTRIB'
    elseif mask & file.IN_CLOSE > 0 then
        event = 'CLOSE'
    elseif mask & file.IN_OPEN > 0 then
        event = 'OPEN'
    elseif mask & file.IN_MOVE > 0 then
        event = 'MOVE'
    elseif mask & file.IN_CREATE > 0 then
        event = 'CREATE'
    elseif mask & file.IN_DELETE > 0 then
        event = 'DELETE'
    elseif mask & file.IN_DELETE_SELF > 0 then
        event = 'DELETE_SELF'
    elseif mask & file.IN_MOVE_SELF > 0 then
        event = 'MOVE_SELF'
    end

    if not event then
        return self:wait(timeout)
    end

    return {
        name = name,
        event = event,
        mask = mask
    }
end

--[[
    wait the next event and return a table represent an event containing the following fields.
      name:  filename associated with the event
      event: event name, supports ACCESS, MODIFY, ATTRIB, CLOSE, OPEN, MOVE, CREATE, DELETE, DELETE_SELF, MOVE_SELF
      mask: contains bits that describe the event that occurred
--]]
function inotify_methods:wait(timeout)
    if self.data then
        return read_inotify_event(self, timeout)
    end

    local data, err = self.rd:read(1024, timeout)
    if not data then
        return nil, err
    end

    self.data = data

    return read_inotify_event(self, timeout)
end

-- add a watch to an initialized inotify instance
-- you can set events be of interest to you via the second argument, defaults to `file.IN_ALL_EVENTS`.
-- return the watch descriptor will be used in `del` method.
function inotify_methods:add(path, mask)
    local wd, err = file.inotify_add_watch(self.fd, path, mask or file.IN_ALL_EVENTS)
    if not wd then
        return nil, err
    end

    self.watchs[wd] = path

    return wd
end

-- remove an existing watch from an inotify instance
-- wd: the watch descriptor returned via `add`
function inotify_methods:del(wd)
    local ok, err = file.inotify_rm_watch(self.fd, wd)
    if not ok then
        return nil, err
    end

    self.watchs[wd] = nil

    return ok
end

function inotify_methods:close()
    if self.fd < 0 then
        return
    end

    file.close(self.fd)
    self.fd = -1
end

local inotify_mt = {
    __index = inotify_methods,
    __gc = inotify_methods.close,
    __close = inotify_methods.close
}

-- create an inotify instance
function M.inotify()
    local fd, err = file.inotify_init()
    if not fd then
        return nil, err
    end

    return setmetatable({
        fd = fd,
        watchs = {},
        rd = eco.reader(fd),
    }, inotify_mt)
end

local function walk(path, cb)
    for name, info in file.dir(path) do
        local sub = path .. name

        local ret = cb(sub, name, info)

        if ret == false then
            return false
        end

        if info.type == 'DIR' and ret ~= M.SKIP then
            if walk(sub .. '/', cb) == false then
                return false
            end
        end
    end
end

-- return false to terminate traversal
-- return file.SKIP to skip traversal of the current directory
function M.walk(root, cb)
    assert(type(root) == 'string', 'root path must be a string')

    if root:sub(#root) ~= '/' then
        root = root .. '/'
    end

    walk(root, cb)
end

return setmetatable(M, { __index = file })
