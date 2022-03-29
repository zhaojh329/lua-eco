#!/usr/bin/env lua

local eco = require "eco"
local IP = require "eco.ip"

local function show_link(ip, ifname)
    if ifname then
        local devs = ip:link("show", ifname)
        for k, v in pairs(info) do
            print(k, v)
        end
    else
        local devs = ip:link()
        for ifname, dev in pairs(devs) do
            print(ifname)
            for k, v in pairs(dev) do
                print("", k, v)
            end
        end
    end
end

local function show_addr(ip, ifname)
    local address

    if ifname then
        address = ip:addr("show", ifname)
    else
        address = ip:addr()
    end

    for _, addr in ipairs(address) do
        print(addr.ifname)
        for k, v in pairs(addr) do
            if k ~= "ifname" then
                print("", k, v)
            end
        end
    end
end

local function wait_link(ip)
    local info = ip:wait()

    for k, v in pairs(info) do
        print(k, v)
    end
end

eco.run(
    function()
        local ip = IP.new()

        local ok, err = ip:link("set", "eth0", { up = true, mtu = 1428 })
        if not ok then error(err) end

        local ok, err = ip:addr("add", "eth0", "192.168.9.1/10")
        if not ok then error(err) end

        show_link(ip)
        show_addr(ip)
        wait_link(ip)
    end
)

eco.loop()
