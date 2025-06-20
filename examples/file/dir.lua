#!/usr/bin/env eco

local file = require 'eco.file'

for name, info in file.dir('.') do
    print(name, 'type: ' .. info['type'], 'uid: ' .. info.uid, 'size: ' .. info.size)
end
