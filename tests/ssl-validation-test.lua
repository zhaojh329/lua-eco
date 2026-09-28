#!/usr/bin/env eco

-- Generate a fresh, trusted test certificate before running:
-- openssl req -x509 -newkey rsa:2048 -nodes -days 1 \
--   -keyout /tmp/eco-validation.key -out /tmp/eco-validation.crt \
--   -subj /CN=wrong.example -addext 'subjectAltName=DNS:server.example,IP:127.0.0.1'
-- eco ssl-validation-test.lua /tmp/eco-validation.crt /tmp/eco-validation.key

local ssl = require 'eco.ssl'
local test = require 'test'

local cert = assert(arg[1], 'certificate path required')
local key = assert(arg[2], 'private key path required')

local function check_connection(name, options, expected)
    test.run_case_async(name, function()
        local server<close> = assert(ssl.listen('127.0.0.1', 0, {
            cert = cert,
            key = key,
            insecure = true
        }))
        local addr = assert(server.sock:getsockname())

        eco.run(function()
            local peer<close>, err = server:accept()
            if expected then
                assert(peer, err)
                assert(peer:send('pong', 2.0))
            end
        end)

        local client<close>, err = ssl.connect('127.0.0.1', addr.port, options)
        if expected then
            assert(client, err)
            assert(client:readfull(4, 2.0) == 'pong')
        else
            assert(client == nil and type(err) == 'string', 'invalid certificate accepted')
        end
    end)
end

check_connection('matching DNS SAN', { ca = cert, server_name = 'server.example' }, true)
check_connection('mismatching DNS SAN', { ca = cert, server_name = 'other.example' }, false)
check_connection('SAN takes precedence over CN', { ca = cert, server_name = 'wrong.example' }, false)
check_connection('explicit secure mode', {
    ca = cert, server_name = 'other.example', insecure = false
}, false)
check_connection('insecure DNS mismatch', {
    ca = cert, server_name = 'other.example', insecure = true
}, true)
check_connection('matching IP SAN', { ca = cert, server_name = '127.0.0.1' }, true)
check_connection('mismatching IP SAN', { ca = cert, server_name = '127.0.0.2' }, false)
check_connection('insecure IP mismatch', {
    ca = cert, server_name = '127.0.0.2', insecure = true
}, true)
check_connection('identity check omitted', { ca = cert }, true)
check_connection('untrusted certificate', { server_name = 'server.example' }, false)
check_connection('insecure untrusted certificate', {
    server_name = 'server.example', insecure = true
}, true)

do
    local ctx<close> = ssl.context()
    assert(ctx:load_ca_cert_file(cert))
    ctx:require_validation(true)

    check_connection('custom secure context', { ctx = ctx, server_name = 'server.example' }, true)
    check_connection('custom secure context mismatch', { ctx = ctx, server_name = 'other.example' }, false)
    check_connection('custom context reused after failure', { ctx = ctx, server_name = 'server.example' }, true)
end

do
    local ctx<close> = ssl.context()
    ctx:require_validation(false)

    check_connection('custom insecure context', {
        ctx = ctx, server_name = 'other.example', insecure = true
    }, true)
end

print('ssl validation tests passed')
