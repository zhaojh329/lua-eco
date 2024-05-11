#!/usr/bin/env eco

local file = require 'eco.file'

local watcher, err = file.inotify()
if not watcher then
    error(err)
end

local wd, err = watcher:add('/tmp/')
if not wd then
    error(err)
end

while true do
    local s, err = watcher:wait()
    if not s then
        error(err)
    end

    print(s.name, s.event, s.mask & file.IN_ISDIR > 0 and 'ISDIR' or '')
end
