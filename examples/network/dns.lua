#!/usr/bin/env eco

local dns = require 'eco.dns'

local answers, err = dns.query('bing.com')

if not answers then
    print('query fail:', err)
    return
end

for _, a in ipairs(answers) do
    for k, v in pairs(a) do
        print(k, v)
    end
    print()
end
