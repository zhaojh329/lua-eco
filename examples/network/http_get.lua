#!/usr/bin/env eco

local http = require 'eco.http.client'

local resp, err = http.get('https://127.0.0.1:8080/test', { insecure = true })
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

print('\nbody:')
if resp.body then
    print(resp.body)
end
