#!/usr/bin/env eco

local http = require 'eco.http.client'

local body = 'abc12345678'

local resp, err = http.post('http://127.0.0.1:8080/test', body)
if not resp then
    print(err)
    return
end

print('code:', resp.code)
print('status:', resp.status)
