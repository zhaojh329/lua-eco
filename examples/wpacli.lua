#!/usr/bin/env lua

local eco = require "eco"
local sys = require "eco.sys"
local file = require "eco.file"
local socket = require "eco.socket"

local function get_status(ifname)
    local s = socket.unix_dgram()

    local path = "/tmp/wpa_ctrl_" .. sys.getpid()

    local ok, err = s:bind(path)
    if not ok then return nil, err end

    file.chown(path, 101, 101)

    ok, err = s:connect("/var/run/wpa_supplicant/" .. ifname)
    if not ok then return nil, err end

    s:send("STATUS")

    local data = s:recv()

    local res = {}

    for l in data:gmatch("[^\n]+") do
        local name, value = l:match("(.+)=(.+)")
        res[name] = value
    end

    return res
end

eco.run(
    function()
        local s, err = get_status("wlan-sta0")
        if not s then
            error(err)
        end

        for k, v in pairs(s) do
            print(k, v)
        end
    end
)

eco.loop()
