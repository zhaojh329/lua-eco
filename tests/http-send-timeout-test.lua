#!/usr/bin/env eco

local http = require 'eco.http.client'
local socket = require 'eco.socket'
local time = require 'eco.time'
local test = require 'test'

local has_ssl, ssl = pcall(require, 'eco.ssl')
local schemes = { 'http' }

if has_ssl then
    schemes[#schemes + 1] = 'https'
else
    print('skip HTTPS send timeout tests: ' .. tostring(ssl))
end

local payload = string.rep('x', 16 * 1024 * 1024)
local path = os.tmpname()

do
    local f<close> = assert(io.open(path, 'wb'))
    assert(f:write(payload))
end

local file_body = assert(http.body_with_file(path))
local field_form = http.form()
assert(field_form:add('field', payload))
local file_form = http.form()
assert(file_form:add_file('file', path))

local cases = {
    { name = 'headers', headers = { ['x-large'] = payload }, err = 'timeout' },
    { name = 'string body', body = payload, err = 'send body fail: timeout' },
    { name = 'file body', body = file_body, err = 'send body fail: timeout' },
    { name = 'multipart field', body = field_form, err = 'send body fail: timeout' },
    { name = 'multipart file', body = file_form, err = 'send body fail: timeout' }
}

for _, scheme in ipairs(schemes) do
    for _, case in ipairs(cases) do
        test.run_case_async(scheme .. ' send timeout: ' .. case.name, function()
            local server, err

            if scheme == 'https' then
                server, err = ssl.listen('127.0.0.1', 0, {
                    cert = 'cert.pem',
                    key = 'key.pem',
                    insecure = true
                })
            else
                server, err = socket.listen_tcp('127.0.0.1', 0)
            end

            assert(server, err)

            local addr = assert((scheme == 'https' and server.sock or server):getsockname())

            eco.run(function()
                local peer = assert(server:accept())

                -- Leave the request unread until well after its send timeout.
                eco.sleep(0.5)

                peer:close()
                server:close()
            end)

            local started = time.now()
            local resp
            resp, err = http.request('POST', scheme .. '://127.0.0.1:' .. addr.port .. '/', case.body, {
                timeout = 0.05,
                headers = case.headers,
                insecure = true
            })

            assert(resp == nil and err == case.err,
                   string.format('expected %s, got %s', case.err, tostring(err)))
            assert(time.now() - started < 0.4, 'request waited for the peer to close')
        end)
    end
end

assert(os.remove(path))
print('HTTP send timeout tests passed')
