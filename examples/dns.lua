#!/usr/bin/env eco

local dns = require 'eco.dns'

local function print_answer(prefix, answers)
    print(prefix)

    for _, a in ipairs(answers) do
        for k, v in pairs(a) do
            if k == 'type' then
                v = dns.type_name(v)
            end
            print(k, v)
        end
        print()
    end
end

local answers, err = dns.query('bing.com')
if not answers then
    print('query fail:', err)
    return
end

print_answer('-----IPv4-----', answers)

answers, err = dns.query('bing.com', { type = dns.TYPE_AAAA })
if not answers then
    print('query fail:', err)
    return
end

print_answer('-----IPv6-----', answers)
