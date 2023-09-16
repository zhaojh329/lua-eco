#!/usr/bin/env eco

local http = require 'eco.http.client'

local resp, err = http.request('https://127.0.0.1:8080', nil, { insecure = true })
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
io.write(resp.read_body(10))
print(resp.read_body(-1))
