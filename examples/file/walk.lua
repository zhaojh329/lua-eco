#!/usr/bin/env eco

local file = require 'eco.file'

--[[
/tmp/root/
├── a
├── b
├── c
│   └── x
└── d
    └── y
--]]

file.walk('/tmp/root', function(path, name, info)
    print(path, 'type: ' .. info['type'], 'uid: ' .. info.uid, 'size: ' .. info.size)

    if path == '/tmp/root/d' then
        return file.SKIP    -- Skip traversal of the current directory
    end

    if path == '/tmp/root/c' then
        return false        -- Terminate traversal
    end
end)
