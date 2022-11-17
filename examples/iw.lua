#!/usr/bin/env lua

local eco = require "eco"
local IW = require "eco.iw"
local IP = require "eco.ip"

local function iw_info(iw, ifname)
    if ifname then
        local info = iw:info(ifname)
        for k, v in pairs(info) do
            print(k, v)
        end
    else
        local devs = iw:info()
        for ifname, info in pairs(devs) do
            print(ifname)
            for k, v in pairs(info) do
                print("", k, v)
            end
        end
    end
end

eco.run(
    function()
        local iw, err = IW.new()
        if not iw then error(err) end

        local ip, err = IP.new()
        if not ip then error(err) end

        local ok, err = iw:add_interface(0, "sta0", "mgd", { addr = "02:00:00:00:00:00" })
        if not ok then error(err) end

        ip:link("set", "sta0", "up")

        local ok, err = iw:scan_trigger("sta0", { freq = {2442, 2437}, ssid = { "test1", "test2" } })
        if not ok then error("scan_trigger: " .. err) end

        local cmd = iw:wait(10.0, IW.NEW_SCAN_RESULTS, IW.SCAN_ABORTED)
        if cmd == IW.SCAN_ABORTED then
            print("aborted")
            return
        end

        local res = iw:scan_dump("sta0")
        for bssid, attr in pairs(res) do
            print(bssid)
            for k, v in pairs(attr) do
                if k == "encryption" then
                    print("", "encryption", v.description)
                else
                    print("", k, v)
                end
            end
        end

        iw:del_interface("sta0")
    end
)

eco.loop()
