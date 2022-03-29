#!/usr/bin/env lua

local eco = require "eco"
local dns = require "eco.dns"

eco.run(
    function()
        --local resolver = dns.resolver()

        local resolver = dns.resolver({
            nameserver = "8.8.8.8",
            timeout = 3.0
        })

        local address = resolver:query("bing.com")

        print(table.concat(address, ", "))
    end
)

eco.loop()
