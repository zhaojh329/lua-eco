#!/usr/bin/env eco

local channel = require 'eco.channel'
local time = require 'eco.time'

-- Create a channel with 5 buffers.
local ch = channel.new(5)

eco.run(function()
    local i = 1
    while true do
        ch:send(i)

        print(os.time(), 'send', i)

        if i == 5 then
            ch:close()
            break
        end

        i = i + 1
        time.sleep(1)
    end
end)

eco.run(function()
    time.sleep(2)
    while true do
        local v = ch:recv()
        if v then
            print(os.time(), 'recv:', v)
        else
            print(os.time(), 'closed')
            break
        end
    end
end)

while true do
    time.sleep(1)
end
