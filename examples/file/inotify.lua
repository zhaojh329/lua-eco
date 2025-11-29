#!/usr/bin/env lua5.4

local file = require 'eco.file'
local eco = require 'eco'

local function event_mask_to_table(mask)
    local events = {}

    if mask & file.IN_ACCESS > 0 then
        events[#events + 1] = 'ACCESS'
    end

    if mask & file.IN_MODIFY > 0 then
        events[#events + 1] = 'MODIFY'
    end

    if mask & file.IN_ATTRIB > 0 then
        events[#events + 1] = 'ATTRIB'
    end

    if mask & file.IN_CLOSE_WRITE > 0 then
        events[#events + 1] = 'CLOSE_WRITE'
    end

    if mask & file.IN_CLOSE_NOWRITE > 0 then
        events[#events + 1] = 'CLOSE_NOWRITE'
    end

    if mask & file.IN_CLOSE > 0 then
        events[#events + 1] = 'CLOSE'
    end

    if mask & file.IN_OPEN > 0 then
        events[#events + 1] = 'OPEN'
    end

    if mask & file.IN_MOVED_FROM > 0 then
        events[#events + 1] = 'MOVED_FROM'
    end

    if mask & file.IN_MOVED_TO > 0 then
        events[#events + 1] = 'MOVED_TO'
    end

    if mask & file.IN_MOVE > 0 then
        events[#events + 1] = 'MOVE'
    end

    if mask & file.IN_CREATE > 0 then
        events[#events + 1] = 'CREATE'
    end

    if mask & file.IN_DELETE > 0 then
        events[#events + 1] = 'DELETE'
    end

    if mask & file.IN_DELETE_SELF > 0 then
        events[#events + 1] = 'DELETE_SELF'
    end

    if mask & file.IN_MOVE_SELF > 0 then
        events[#events + 1] = 'MOVE_SELF'
    end

    return events
end

local watcher, err = file.inotify()
if not watcher then
    error(err)
end

local wd, err = watcher:add('/tmp/')
if not wd then
    error(err)
end

eco.run(function()
    while true do
        local ev, err = watcher:wait()
        if not ev then
            error(err)
        end

        local events = event_mask_to_table(ev.mask)

        print(ev.name, table.concat(events, ' '), ev.mask & file.IN_ISDIR > 0 and 'ISDIR' or '')
    end
end)

eco.loop()
