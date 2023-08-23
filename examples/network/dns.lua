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

answers, err = dns.query('bing.com', { type = dns.TYPE_AAAA })
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
