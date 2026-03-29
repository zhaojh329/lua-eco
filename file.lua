-- SPDX-License-Identifier: MIT
-- Author: Jianhui Zhao <zhaojh329@gmail.com>

--- File utilities.
--
-- This module provides file and filesystem related helpers, bind common POSIX file APIs.
--
-- Exported constants:
--
-- - open(2) flags: `O_RDONLY`, `O_WRONLY`, `O_RDWR`, `O_APPEND`, `O_CLOEXEC`,
--   `O_CREAT`, `O_EXCL`, `O_NOCTTY`, `O_NONBLOCK`, `O_TRUNC`
-- - stat(2) mode bits: `S_IRWXU`, `S_IRUSR`, `S_IWUSR`, `S_IXUSR`, `S_IRWXG`,
--   `S_IRGRP`, `S_IWGRP`, `S_IXGRP`, `S_IRWXO`, `S_IROTH`, `S_IWOTH`,
--   `S_IXOTH`, `S_ISUID`, `S_ISGID`, `S_ISVTX`
-- - lseek(2) whence: `SEEK_SET`, `SEEK_CUR`, `SEEK_END`
-- - flock(2) operations: `LOCK_SH`, `LOCK_EX`, `LOCK_UN`
-- - inotify(7) masks: `IN_ACCESS`, `IN_MODIFY`, `IN_ATTRIB`, `IN_CLOSE_WRITE`,
--   `IN_CLOSE_NOWRITE`, `IN_CLOSE`, `IN_OPEN`, `IN_MOVED_FROM`, `IN_MOVED_TO`,
--   `IN_MOVE`, `IN_CREATE`, `IN_DELETE`, `IN_DELETE_SELF`, `IN_MOVE_SELF`,
--   `IN_ALL_EVENTS`, `IN_ISDIR`
--
-- @module eco.file

local file = require 'eco.internal.file'
local time = require 'eco.time'
local sys = require 'eco.sys'
local eco = require 'eco'

local M = {
    --- Special return value for @{walk} callback to skip descending into the current directory.
    SKIP = 1
}

--- Read contents from a file.
--
-- Opens the file in read-only mode and reads data using `file:read`.
-- The file handle is automatically closed after use.
--
-- @function readfile
-- @tparam string path Path of the file to read.
-- @tparam[opt='*a'] string|number m Read mode passed to `file:read`.
--
--   - 'a': read the whole file (default)
--   - 'l': read a line without newline
--   - 'L': read a line with newline
--   - 'n': read a number
--   - int: read specified number of bytes
--
-- @treturn any Result returned by `file:read` on success.
-- @treturn[2] nil On failure to open file.
-- @treturn[2] string Error message when failed.
-- @usage
-- local data, err = file.readfile('/etc/os-release')
-- if not data then
--     print('readfile failed:', err)
-- end
function M.readfile(path, m)
    local f<close>, err = io.open(path, 'r')
    if not f then
        return nil, err
    end

    return f:read(m or '*a')
end

--- Write data to a file.
--
-- Opens the file in write mode (`'w'`) by default, or append mode (`'a'`) when `append` is true.
--
-- @function writefile
-- @tparam string path Path of the file to write.
-- @tparam string data Data to write.
-- @tparam[opt=false] boolean append Append instead of truncate.
-- @treturn boolean true On success.
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
-- @usage
-- local ok, err = file.writefile('/tmp/out.txt', 'hello\n')
-- assert(ok, err)
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

--- File object returned by @{open}.
--
-- This object wraps a file descriptor.
--
-- @type file
local file_methods = {}

--- See @{eco.reader:read}
-- @function file:read
function file_methods:read(format, timeout)
    return self.rd:read(format, timeout)
end

--- See @{eco.reader:readfull}
-- @function file:readfull
function file_methods:readfull(format, timeout)
    return self.rd:readfull(format, timeout)
end

--- See @{eco.reader:readuntil}
-- @function file:readuntil
function file_methods:readuntil(format, timeout)
    return self.rd:readuntil(format, timeout)
end

--- See @{eco.writer:write}
-- @function file:write
function file_methods:write(data, timeout)
    return self.wr:write(data, timeout)
end

--- Reposition read/write file offset.
--
-- @function file:lseek
-- @tparam int offset Offset.
-- @tparam int where One of `file.SEEK_SET`, `file.SEEK_CUR`, `file.SEEK_END`.
-- @treturn int New offset on success.
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
function file_methods:lseek(offset, where)
    return file.lseek(self.fd, offset, where)
end

--- Get file status.
--
-- Thin wrapper around POSIX `fstat(2)`.
--
-- @function stat
-- @treturn table See @{file.stat}.
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
function file_methods:stat()
    return file.fstat(self.fd)
end

--- Acquire or release an advisory file lock.
--
-- @function flock
-- @tparam int fd File descriptor.
-- @tparam int operation Lock operation (`file.LOCK_SH`, `file.LOCK_EX`, `file.LOCK_UN`).
-- @tparam[opt] number timeout Timeout in seconds.
-- @treturn boolean true On success.
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message (or `'timeout'`).
function file_methods:flock(operation, timeout)
    local sleep_time = 0.001
    local max_sleep = 0.05
    local deadtime

    if timeout then
        deadtime = sys.uptime() + timeout
    end

    while true do
        local ok, errno = file.flock(self.fd, operation)
        if ok then
            return true
        end

        if errno ~= sys.EAGAIN and errno ~= sys.EWOULDBLOCK then
            return nil, sys.strerror(errno)
        end

        local delay = sleep_time + sleep_time * 0.2 * math.random()

        if deadtime then
            local left = deadtime - sys.uptime()

            if left <= 0 then
                return nil, 'timeout'
            end

            if delay > left then
                delay = left
            end
        end

        time.sleep(delay)

        if sleep_time < max_sleep then
            sleep_time = sleep_time * 2
            if sleep_time > max_sleep then
                sleep_time = max_sleep
            end
        end
    end
end

--- Close the file.
--
-- This is idempotent and is also used as the `__gc` / `__close` metamethod.
--
-- @function file:close
function file_methods:close()
    if self.fd < 0 then
        return
    end

    file.close(self.fd)
    self.fd = -1
end

--- End of `file` class section.
-- @section end

local file_mt = {
    __index = file_methods,
    __gc = file_methods.close,
    __close = file_methods.close
}

--- Open and possibly create a file
--
-- @function open
-- @tparam string path Path of the file.
-- @tparam[opt=file.O_RDONLY] int flags Open flags (bitwise OR of `file.O_*` constants).
-- @tparam[opt=0] int mode File mode bits (bitwise OR of `file.S_I*` constants, only meaningful with flag `file.O_CREAT`).
-- @treturn file File object on success.
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
function M.open(path, flags, mode)
    local fd, err = file.open(path, flags, mode)
    if not fd then
        return nil, err
    end

    return setmetatable({
        fd = fd,
        rd = eco.reader(fd),
        wr = eco.writer(fd)
    }, file_mt)
end

--- Inotify handle returned by @{inotify}.
--
-- @type inotify
local inotify_methods = {}

local function read_inotify_event(self, timeout)
    local events = self.events
    local ev = events[1]

    table.remove(events, 1)

    local path = self.watchs[ev.wd]
    if not path then
        return self:wait(timeout)
    end

    local name = ev.name

    if name then
        if path:sub(#path) ~= '/' then
            path = path .. '/'
        end

        name = path .. name
    else
        name = path
    end

    return {
        name = name,
        mask = ev.mask
    }
end

--- Wait for an inotify event.
--
-- If there are already parsed events buffered in the watcher, returns the next
-- one immediately; otherwise, reads from the underlying inotify fd.
--
-- The returned event is a table with fields:
--
-- - `name`: full path of the affected entry
-- - `mask`: inotify mask bits (`file.IN_ACCESS`, `file.IN_MODIFY`, `file.IN_OPEN`,...)
--
-- @function inotify:wait
-- @tparam[opt] number timeout Timeout in seconds.
-- @treturn table Event table `{ name = string, mask = int }`.
-- @treturn[2] nil On timeout or error.
-- @treturn[2] string Error message.
-- @usage
-- local w = assert(file.inotify())
-- assert(w:add('/tmp', file.IN_CREATE | file.IN_DELETE))
-- while true do
--     local ev = assert(w:wait())
--     print(ev.name, ev.mask)
-- end
function inotify_methods:wait(timeout)
    if #self.events > 0 then
        return read_inotify_event(self, timeout)
    end

    local data, err = self.rd:read(1024, timeout)
    if not data then
        return nil, err
    end

    self.events = file.inotify_parse_event(data)

    return read_inotify_event(self, timeout)
end

--- Add a path to be watched.
--
-- @function inotify:add
-- @tparam string path Path to watch.
-- @tparam[opt] int mask Event mask. Defaults to `file.IN_ALL_EVENTS`.
-- @treturn int Watch descriptor (`wd`).
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
-- @usage
-- local w = assert(file.inotify())
-- local wd = assert(w:add('/tmp', file.IN_CREATE))
function inotify_methods:add(path, mask)
    local wd, err = file.inotify_add_watch(self.fd, path, mask or file.IN_ALL_EVENTS)
    if not wd then
        return nil, err
    end

    self.watchs[wd] = path

    return wd
end

--- Remove a watch by its watch descriptor.
--
-- @function inotify:del
-- @tparam int wd Watch descriptor returned by @{inotify:add}.
-- @treturn boolean true On success.
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
function inotify_methods:del(wd)
    local ok, err = file.inotify_rm_watch(self.fd, wd)
    if not ok then
        return nil, err
    end

    self.watchs[wd] = nil

    return ok
end

--- Close the watcher.
--
-- @function inotify:close
function inotify_methods:close()
    if self.fd < 0 then
        return
    end

    file.close(self.fd)
    self.fd = -1
end

--- End of `inotify` class section.
-- @section end

local inotify_mt = {
    __index = inotify_methods,
    __gc = inotify_methods.close,
    __close = inotify_methods.close
}

--- Create an inotify watcher.
--
-- @function inotify
-- @treturn inotify Watcher object.
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
-- @usage
-- local w, err = file.inotify()
-- assert(w, err)
-- local wd = assert(w:add('/tmp', file.IN_CREATE | file.IN_DELETE))
-- while true do
--     local ev = assert(w:wait())
--     print(ev.name, ev.mask)
-- end
function M.inotify()
    local fd, err = file.inotify_init()
    if not fd then
        return nil, err
    end

    return setmetatable({
        fd = fd,
        watchs = {},
        events = {},
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

--- Recursively traverse a directory tree.
--
-- For each entry under `root`, invokes `cb(fullpath, name, info)`.
-- `info` is the same table returned by @{dir}.
--
-- Callback return values:
--
-- - `false`: terminate traversal
-- - @{file.SKIP}: if the current entry is a directory, do not descend into it
-- - anything else / nil: continue
--
-- @function walk
-- @tparam string root Root directory.
-- @tparam function cb Callback function.
-- @usage
-- file.walk('/etc', function(path, name, info)
--     print(path, info.type)
--     if name == '.git' then
--         return file.SKIP
--     end
-- end)
function M.walk(root, cb)
    assert(type(root) == 'string', 'root path must be a string')

    if root:sub(#root) ~= '/' then
        root = root .. '/'
    end

    walk(root, cb)
end

return setmetatable(M, { __index = file })
