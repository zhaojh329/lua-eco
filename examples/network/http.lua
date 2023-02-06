#!/usr/bin/env eco

local http = require 'eco.http'

local resp, err = http.request('https://bing.com')
if not resp then
    print(err)
    return
end

print('code:', resp.code)
print('status:', resp.status)

print('\nheaders:')
for name, value in pairs(resp.headers) do
    print('', name .. ': ' .. value)
end

print('\nbody:', resp.body)
