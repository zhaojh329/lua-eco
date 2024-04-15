#!/usr/bin/env eco

local http = require 'eco.http.client'

local resp, err = http.get('http://127.0.0.1:8080/test', { body_to_file = 'test.txt' })
if not resp then
    print(err)
    return
end

print('code:', resp.code)
print('status:', resp.status)
