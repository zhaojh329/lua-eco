#!/usr/bin/env eco

local base64 = require 'eco.encoding.base64'
local sha1 = require 'eco.hash.sha1'

local WS_GUID = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11'

local function accept_for(key)
    return base64.encode(sha1.sum(key .. WS_GUID))
end

local function with_websocket(make_response, fn)
    local saved_http = package.loaded['eco.http.client']
    local state = {
        closed = false,
        sock = {}
    }

    local fake_http = {}

    function fake_http.new()
        local hc = {}

        function hc:request(method, uri, body, opts)
            state.method = method
            state.uri = uri
            state.body = body
            state.opts = opts
            state.headers = opts.headers

            return make_response(state)
        end

        function hc:close()
            state.closed = true
        end

        function hc:sock()
            return state.sock
        end

        return hc
    end

    package.loaded['eco.http.client'] = fake_http

    local ok, websocket_or_err = pcall(dofile, 'websocket.lua')

    package.loaded['eco.http.client'] = saved_http

    assert(ok, websocket_or_err)

    return fn(websocket_or_err, state)
end

local function good_response(state, overrides)
    local key = state.headers['sec-websocket-key']
    local headers = {
        upgrade = 'websocket',
        connection = 'keep-alive, Upgrade',
        ['sec-websocket-accept'] = accept_for(key)
    }

    for k, v in pairs(overrides or {}) do
        headers[k] = v
    end

    return {
        code = 101,
        headers = headers
    }
end

local function expect_failure(name, make_response, expected_err, opts)
    with_websocket(make_response, function(websocket, state)
        local ws, err = websocket.connect('ws://example.test/ws', opts)

        assert(ws == nil, name .. ': expected connect failure')
        assert(err == expected_err, name .. ': unexpected error: ' .. tostring(err))
        assert(state.closed == true, name .. ': http client should be closed')
    end)
end

with_websocket(function(state)
    assert(state.method == 'GET')
    assert(state.uri == 'ws://example.test/ws')
    assert(state.headers.connection == 'upgrade')
    assert(state.headers.upgrade == 'websocket')
    assert(state.headers['sec-websocket-version'] == '13')
    assert(state.headers['sec-websocket-protocol'] == 'chat,echo')
    assert(state.headers['x-extra'] == '1')

    local raw = assert(base64.decode(state.headers['sec-websocket-key']))
    assert(#raw == 16)

    return good_response(state, {
        ['sec-websocket-protocol'] = 'chat'
    })
end, function(websocket, state)
    local ws, err = websocket.connect('ws://example.test/ws', {
        protocols = { 'chat', 'echo' },
        headers = {
            ['X-Extra'] = '1',
            ['Sec-WebSocket-Key'] = 'attacker-controlled'
        }
    })

    assert(ws, err)
    assert(ws.sock == state.sock)
    assert(state.closed == false)
    assert(state.headers['sec-websocket-key'] ~= 'attacker-controlled')
end)

expect_failure('bad accept', function(state)
    return good_response(state, {
        ['sec-websocket-accept'] = 'bad'
    })
end, 'bad "sec-websocket-accept" response header')

expect_failure('bad upgrade', function(state)
    return good_response(state, {
        upgrade = 'h2c'
    })
end, 'bad "upgrade" response header')

expect_failure('bad connection', function(state)
    return good_response(state, {
        connection = 'close'
    })
end, 'bad "connection" response header')

expect_failure('unexpected protocol', function(state)
    return good_response(state, {
        ['sec-websocket-protocol'] = 'other'
    })
end, 'bad "sec-websocket-protocol" response header', {
    protocols = { 'chat' }
})

print('websocket client handshake tests passed')
