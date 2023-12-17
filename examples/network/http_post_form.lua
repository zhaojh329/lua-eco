#!/usr/bin/env eco

local http = require 'eco.http.client'

local form = http.form()

form:add('name', 'eco')
form:add('age', '123')

local ok, err = form:add_file('file', 'test.bin')
if not ok then
    error(err)
end

local resp, err = http.post('http://127.0.0.1:8080/upload', form)
if not resp then
    print(err)
    return
end

print('code:', resp.code)
print('status:', resp.status)
