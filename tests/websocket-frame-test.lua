#!/usr/bin/env eco

local websocket = require 'eco.websocket'

local function make_con(sock)
    local con = {
        resp = {
            head_sent = false
        },
        sock = sock,
        headers = {}
    }

    function con:discard_body()
        return true
    end

    function con:set_status(status)
        self.status = status
    end

    function con:add_header(name, value)
        self.headers[name] = value
    end

    function con:flush()
        return true
    end

    return con
end

local function make_req()
    return {
        major_version = 1,
        minor_version = 1,
        headers = {
            upgrade = 'websocket',
            connection = 'upgrade',
            ['sec-websocket-version'] = '13',
            ['sec-websocket-key'] = 'dGhlIHNhbXBsZSBub25jZQ=='
        }
    }
end

local function make_sock(chunks, expected_timeout)
    local sock = {
        chunks = chunks,
        reads = 0
    }

    function sock:readfull(n, timeout)
        self.reads = self.reads + 1

        if expected_timeout ~= nil then
            assert(timeout == expected_timeout,
                   string.format('unexpected timeout: %s', tostring(timeout)))
        end

        local chunk = self.chunks[self.reads]
        assert(chunk and #chunk == n,
               string.format('unexpected read size: want %d got %s',
                             n, chunk and #chunk or 'nil'))

        return chunk
    end

    return sock
end

do
    local payload = string.rep('x', 70000)
    local frame_head = string.char(0x82, 127)
    local frame_len = string.pack('>I4I4', 0, #payload)
    local sock = make_sock({ frame_head, frame_len, payload }, 3.5)
    local ws = assert(websocket.upgrade(make_con(sock), make_req(), {
        max_payload_len = #payload
    }))

    local data, typ, err = ws:recv_frame(3.5)

    assert(data == payload, err)
    assert(typ == 'binary')
    assert(err == nil)
    assert(sock.reads == 3)
end

do
    local frame_head = string.char(0x82, 127)
    local frame_len = string.pack('>I4I4', 0x80000000, 0)
    local sock = make_sock({ frame_head, frame_len }, 2.0)
    local ws = assert(websocket.upgrade(make_con(sock), make_req(), {
        max_payload_len = math.maxinteger
    }))

    local data, typ, err = ws:recv_frame(2.0)

    assert(data == nil and typ == nil and err == 'payload len too large')
    assert(sock.reads == 2)
end

print('websocket frame tests passed')
