-- SPDX-License-Identifier: MIT
-- Author: Jianhui Zhao <zhaojh329@gmail.com>

--- File utilities.
--
-- This module provides file and filesystem related helpers.
--
-- @module eco.file

local file = require 'eco.internal.file'
local time = require 'eco.time'
local sys = require 'eco.sys'
local eco = require 'eco'

local M = {
    --- Special return value for @{walk} callback to skip descending into the current directory.
    SKIP = 1,

    --- `open(2)` flag: open for reading only.
    O_RDONLY = file.O_RDONLY,
    --- `open(2)` flag: open for writing only.
    O_WRONLY = file.O_WRONLY,
    --- `open(2)` flag: open for reading and writing.
    O_RDWR = file.O_RDWR,
    --- `open(2)` flag: if pathname does not exist, create it as a regular file.
    O_CREAT = file.O_CREAT,

    --- `open(2)` mode bit: owner has read permission.
    S_IRUSR = file.S_IRUSR,
    --- `open(2)` mode bit: owner has write permission.
    S_IWUSR = file.S_IWUSR,
    --- `open(2)` mode bit: owner has execute permission.
    S_IXUSR = file.S_IXUSR,

    --- `lseek(2)` whence: seek from beginning of file.
    SEEK_SET = file.SEEK_SET,
    --- `lseek(2)` whence: seek from current file offset.
    SEEK_CUR = file.SEEK_CUR,
    --- `lseek(2)` whence: seek from end of file.
    SEEK_END = file.SEEK_END,

    --- `flock(2)` operation: shared lock.
    LOCK_SH = file.LOCK_SH,
    --- `flock(2)` operation: exclusive lock.
    LOCK_EX = file.LOCK_EX,
    --- `flock(2)` operation: unlock.
    LOCK_UN = file.LOCK_UN,

    --- `inotify(7)` event: file was accessed.
    IN_ACCESS = file.IN_ACCESS,
    --- `inotify(7)` event: file was modified.
    IN_MODIFY = file.IN_MODIFY,
    --- `inotify(7)` event: metadata changed (permissions, timestamps, etc).
    IN_ATTRIB = file.IN_ATTRIB,
    --- `inotify(7)` event: writable file was closed.
    IN_CLOSE_WRITE = file.IN_CLOSE_WRITE,
    --- `inotify(7)` event: non-writable file was closed.
    IN_CLOSE_NOWRITE = file.IN_CLOSE_NOWRITE,
    --- `inotify(7)` event: file was closed (write or nowrite).
    IN_CLOSE = file.IN_CLOSE,
    --- `inotify(7)` event: file was opened.
    IN_OPEN = file.IN_OPEN,
    --- `inotify(7)` event: file moved out of watched directory.
    IN_MOVED_FROM = file.IN_MOVED_FROM,
    --- `inotify(7)` event: file moved into watched directory.
    IN_MOVED_TO = file.IN_MOVED_TO,
    --- `inotify(7)` event: file moved (from or to).
    IN_MOVE = file.IN_MOVE,
    --- `inotify(7)` event: file/directory created in watched directory.
    IN_CREATE = file.IN_CREATE,
    --- `inotify(7)` event: file/directory deleted from watched directory.
    IN_DELETE = file.IN_DELETE,
    --- `inotify(7)` event: watched file/directory itself was deleted.
    IN_DELETE_SELF = file.IN_DELETE_SELF,
    --- `inotify(7)` event: watched file/directory itself was moved.
    IN_MOVE_SELF = file.IN_MOVE_SELF,
    --- `inotify(7)` mask: all standard events.
    IN_ALL_EVENTS = file.IN_ALL_EVENTS,
    --- `inotify(7)` flag: subject of event is a directory.
    IN_ISDIR = file.IN_ISDIR,
}

---
-- Read contents from a file.
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

---
-- Write data to a file.
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

---
-- File object returned by @{open}.
--
-- This object wraps a file descriptor.
--
-- @type file
local file_methods = {}

--- Read data from the file.
--
-- This calls `eco.reader:read` on the underlying file descriptor.
--
-- @function file:read
-- @tparam int expected Number of bytes to read (must be > 0).
-- @tparam[opt] number timeout Timeout in seconds.
-- @treturn string Data read.
-- @treturn[2] nil On timeout, EOF, or error.
-- @treturn[2] string Error message (including `'eof'`).
function file_methods:read(n, timeout)
    return self.rd:read(n, timeout)
end

--- Read into a buffer.
--
-- This calls `eco.reader:read2b` on the underlying file descriptor.
--
-- @function file:read2b
-- @tparam buffer b An @{eco.buffer} object.
-- @tparam int expected Number of bytes expected to read (cannot be 0).
-- @tparam[opt] number timeout Timeout in seconds.
-- @treturn int bytes Number of bytes actually read.
-- @treturn[2] nil On error or EOF.
-- @treturn[2] string Error message or `'eof'`.
function file_methods:read2b(b, n, timeout)
    return self.rd:read2b(b, n, timeout)
end

--- Write data to the file.
--
-- @function file:write
-- @tparam string data Data to write.
-- @treturn int bytes Number of bytes written.
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
function file_methods:write(data)
    return file.write(self.fd, data)
end

--- Reposition read/write file offset.
--
-- @function file:lseek
-- @tparam int offset Offset.
-- @tparam int where One of @{file.SEEK_SET}, @{file.SEEK_CUR}, @{file.SEEK_END}.
-- @treturn int New offset on success.
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
function file_methods:lseek(offset, where)
    return file.lseek(self.fd, offset, where)
end

---
-- Acquire or release an advisory file lock.
--
-- @function flock
-- @tparam int fd File descriptor.
-- @tparam int operation Lock operation (@{file.LOCK_SH}, @{file.LOCK_EX}, @{file.LOCK_UN}).
-- @tparam[opt] number timeout Timeout in seconds.
-- @treturn boolean true On success.
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message (or `'timeout'`).
function file_methods:flock(operation, timeout)
    local deadtime

    if timeout then
        deadtime = sys.uptime() + timeout
    end

    while true do
        local ok, errno = file.flock(self.fd, operation)
        if ok then
            return true
        end

        if errno ~= sys.EAGAIN then
            return nil, sys.strerror(errno)
        end

        if deadtime and sys.uptime() > deadtime then
            return nil, 'timeout'
        end

        time.sleep(0.1)
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

---
-- Open and possibly create a file
--S_IRUSR
-- @function open
-- @tparam string path Path of the file.
-- @tparam[opt=file.O_RDONLY] int flags Open flags (bitwise OR of `file.O_*` constants).
-- @tparam[opt=0] int mode File mode bits (bitwise OR of `file.S_I*` constants, only meaningful with flag @{file.O_CREAT}).
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
        rd = eco.reader(fd)
    }, file_mt)
end

---
-- Flush filesystem buffers.
--
-- Executes the system `sync(1)` command via @{eco.sys.exec} and waits for it.
--
-- @function sync
-- @tparam[opt] number timeout Timeout in seconds.
-- @treturn int Process id.
-- @treturn int Exit status.
-- @treturn[2] nil On timeout or failure.
-- @treturn[2] string Error message.
function M.sync(timeout)
    local p<close>, err = sys.exec('sync')
    if not p then
        return nil, err
    end

    return p:wait(timeout)
end

---
-- Inotify handle returned by @{inotify}.
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
-- - `mask`: inotify mask bits (@{file.IN_ACCESS}, @{file.IN_MODIFY}, @{file.IN_OPEN},...)
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
-- @tparam[opt] int mask Event mask. Defaults to @{file.IN_ALL_EVENTS}.
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

---
-- Create an inotify watcher.
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

---
-- Recursively traverse a directory tree.
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
