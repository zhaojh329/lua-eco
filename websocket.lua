-- SPDX-License-Identifier: MIT
-- Author: Jianhui Zhao <zhaojh329@gmail.com>

-- Referenced from https://github.com/openresty/lua-resty-websocket

local base64 = require 'eco.encoding.base64'
local http = require 'eco.http.client'
local sha1 = require 'eco.hash.sha1'
local bufio = require 'eco.bufio'

local tostring = tostring
local concat = table.concat
local rand = math.random
local str_char = string.char
local str_byte = string.byte
local str_lower = string.lower
local str_sub = string.sub
local type = type

--- WebSocket client/server helpers.
--
-- This module implements basic WebSocket framing and the HTTP upgrade
-- handshake.
--
-- It can be used in two ways:
--
-- - Server side: call @{websocket.upgrade} from an @{eco.http.server} request handler.
-- - Client side: call @{websocket.connect} to perform the upgrade handshake and obtain a
--   WebSocket connection.
--
-- The returned @{connection} object supports sending and receiving individual
-- WebSocket frames. Fragmented messages are not automatically reassembled; see
-- @{connection:recv_frame} for the `err == 'again'` convention.
--
-- @module eco.websocket

local M = {}

local types = {
    [0x0] = 'continuation',
    [0x1] = 'text',
    [0x2] = 'binary',
    [0x8] = 'close',
    [0x9] = 'ping',
    [0xa] = 'pong',
}

--- Options table for WebSocket connections.
-- @table WebSocketOptions
-- @tfield[opt=65535] integer max_payload_len Maximum payload length accepted/sent.

--- Options table for @{websocket.connect}.
-- @table ConnectOptions
-- @tfield[opt] table headers Extra HTTP headers to send during handshake.
-- @tfield[opt] string|table protocols `Sec-WebSocket-Protocol` value.
--   If a table is provided, it will be joined using commas.
-- @tfield[opt] string origin `Origin` header value.
-- @tfield[opt] boolean insecure Passed to @{eco.http.client} (TLS verify control).
-- @tfield[opt] number timeout Request timeout in seconds (passed to HTTP client).
-- @tfield[opt=65535] integer max_payload_len Maximum payload length accepted/sent.

--- WebSocket connection returned by @{websocket.upgrade} or @{websocket.connect}.
--
-- @type connection
local methods = {}

--- Receive a single WebSocket frame.
--
-- Return convention:
--
-- - On success: `data, typ, err`
-- - On failure: `nil, nil, err`
--
-- `typ` is one of: `'text'`, `'binary'`, `'continuation'`, `'close'`, `'ping'`, `'pong'`.
--
-- For `typ == 'close'`, `err` carries the close status code (number) when
-- present, and `data` carries the close reason string.
--
-- For fragmented messages, `err == 'again'` indicates that more frames are
-- expected to complete the message.
--
-- @function connection:recv_frame
-- @tparam[opt] number timeout Timeout in seconds.
-- @treturn string data Frame payload.
-- @treturn string typ Frame type.
-- @treturn[opt] any err Extra information (`'again'` for fragmentation, or close code).
-- @treturn[2] nil On failure.
-- @treturn[2] nil On failure.
-- @treturn[2] string err Error message.
function  methods:recv_frame(timeout)
    local opts = self.opts
    local b = self.b

    local data, err = b:readfull(2, timeout)
    if not data then
        return nil, nil, 'failed to receive the first 2 bytes: ' .. err
    end

    timeout = 1.0

    local fst, snd = str_byte(data, 1, 2)

    local fin = fst & 0x80 ~= 0

    if fst & 0x70 ~= 0 then
        return nil, nil, 'bad RSV1, RSV2, or RSV3 bits'
    end

    local opcode = fst & 0x0f

    if opcode >= 0x3 and opcode <= 0x7 then
        return nil, nil, 'reserved non-control frames'
    end

    if opcode >= 0xb and opcode <= 0xf then
        return nil, nil, 'reserved control frames'
    end

    local mask = snd & 0x80 ~= 0

    local payload_len = snd & 0x7f

    if payload_len == 126 then
        data, err = b:readfull(2, timeout)
        if not data then
            return nil, nil, 'failed to receive the 2 byte payload length: ' .. err
        end

        payload_len = string.unpack('>I2', data)

    elseif payload_len == 127 then
        data, err = b:readfull(2, timeout)
        if not data then
            return nil, nil, 'failed to receive the 8 byte payload length: ' .. err
        end

        if str_byte(data, 1) ~= 0 or str_byte(data, 2) ~= 0 or str_byte(data, 3) ~= 0 or str_byte(data, 4) ~= 0 then
            return nil, nil, 'payload len too large'
        end

        local fifth = str_byte(data, 5)
        if fifth & 0x80 ~= 0 then
            return nil, nil, 'payload len too large'
        end

        payload_len = string.unpack('>I4', data:sub(5))
    end

    if opcode & 0x8 ~= 0 then
        -- being a control frame
        if payload_len > 125 then
            return nil, nil, 'too long payload for control frame'
        end

        if not fin then
            return nil, nil, 'fragmented control frame'
        end
    end

    if payload_len > opts.max_payload_len then
        return nil, nil, 'exceeding max payload len'
    end

    local rest
    if mask then
        rest = payload_len + 4
    else
        rest = payload_len
    end

    if rest > 0 then
        timeout = 10.0
        data, err = b:readfull(rest, timeout)
        if not data then
            return nil, nil, 'failed to read masking-len and payload: ' .. err
        end
    else
        data = ''
    end

    if opcode == 0x8 then
        -- being a close frame
        if payload_len > 0 then
            if payload_len < 2 then
                return nil, nil, 'close frame with a body must carry a 2-byte status code'
            end

            local msg, code
            if mask then
                fst = str_byte(data, 4 + 1) ~ str_byte(data, 1)
                snd = str_byte(data, 4 + 2) ~ str_byte(data, 2)
                code = fst << 8 | snd

                if payload_len > 2 then
                    msg = {}
                    for i = 3, payload_len do
                        msg[i - 2] = str_char(str_byte(data, 4 + i) ~ str_byte(data, (i - 1) % 4 + 1))
                    end

                    msg = concat(msg)
                else
                    msg = ''
                end
            else
                code = string.unpack('>I2', data)

                if payload_len > 2 then
                    msg = str_sub(data, 3)
                else
                    msg = ''
                end
            end

            return msg, 'close', code
        end

        return '', 'close', nil
    end

    local msg
    if mask then
        msg = {}
        for i = 1, payload_len do
            msg[i] = str_char(str_byte(data, 4 + i) ~ str_byte(data, (i - 1) % 4 + 1))
        end
        msg = concat(msg)
    else
        msg = data
    end

    return msg, types[opcode], not fin and 'again' or nil
end

local function build_frame(fin, opcode, payload_len, payload, masking)
    local fst
    if fin then
        fst = 0x80 | opcode
    else
        fst = opcode
    end

    local snd, extra_len_bytes
    if payload_len <= 125 then
        snd = payload_len
        extra_len_bytes = ''

    elseif payload_len <= 65535 then
        snd = 126
        extra_len_bytes = string.pack('>I2', payload_len)
    else
        if payload_len & 0x7fffffff < payload_len then
            return nil, 'payload too big'
        end

        snd = 127
        -- XXX we only support 31-bit length here
        extra_len_bytes = string.pack('>I4I4', 0, payload_len)
    end

    local masking_key
    if masking then
        -- set the mask bit
        snd = snd | 0x80
        local key = rand(0xffffff)
        masking_key = string.pack('>I4', key)

        local masked = {}
        for i = 1, payload_len do
            masked[i] = str_char(str_byte(payload, i) ~ str_byte(masking_key, (i - 1) % 4 + 1))
        end
        payload = concat(masked)

    else
        masking_key = ''
    end

    return str_char(fst, snd) .. extra_len_bytes .. masking_key .. payload
end

--- Send a raw WebSocket frame.
--
-- `opcode` values follow RFC 6455:
--
-- - `0x1` text
-- - `0x2` binary
-- - `0x8` close
-- - `0x9` ping
-- - `0xA` pong
--
-- @function connection:send_frame
-- @tparam boolean fin Whether this is the final fragment.
-- @tparam integer opcode Frame opcode.
-- @tparam[opt] string payload Frame payload (will be converted to string if not already).
-- @treturn integer bytes Bytes sent.
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
function methods:send_frame(fin, opcode, payload)
    local sock = self.sock
    local opts = self.opts

    if not payload then
        payload = ''

    elseif type(payload) ~= 'string' then
        payload = tostring(payload)
    end

    local payload_len = #payload

    if payload_len > opts.max_payload_len then
        return nil, 'payload too big'
    end

    if opcode & 0x8 ~= 0 then
        -- being a control frame
        if payload_len > 125 then
            return nil, 'too much payload for control frame'
        end
        if not fin then
            return nil, 'fragmented control frame'
        end
    end

    local frame, err = build_frame(fin, opcode, payload_len, payload, self.masking)
    if not frame then
        return nil, 'failed to build frame: ' .. err
    end

    local bytes, err = sock:send(frame)
    if not bytes then
        return nil, 'failed to send frame: ' .. err
    end
    return bytes
end

--- Send a text frame.
-- @function connection:send_text
-- @tparam[opt] string data Text payload.
-- @treturn integer bytes Bytes sent.
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
function methods:send_text(data)
    return self:send_frame(true, 0x1, data)
end

--- Send a binary frame.
-- @function connection:send_binary
-- @tparam[opt] string data Binary payload.
-- @treturn integer bytes Bytes sent.
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
function methods:send_binary(data)
    return self:send_frame(true, 0x2, data)
end

--- Send a close frame.
--
-- @function connection:send_close
-- @tparam[opt] integer code Close status code.
-- @tparam[opt] string msg Close reason.
-- @treturn integer bytes Bytes sent.
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
function methods:send_close(code, msg)
    local payload
    if code then
        if type(code) ~= 'number' or code > 0x7fff then
            return nil, 'bad status code'
        end
        payload = str_char(code >> 8 & 0xff, code & 0xff) .. (msg or '')
    end
    return self:send_frame(true, 0x8, payload)
end

--- Send a ping frame.
-- @function connection:send_ping
-- @tparam[opt] string data Payload.
-- @treturn integer bytes Bytes sent.
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
function methods:send_ping(data)
    return self:send_frame(true, 0x9, data)
end


--- Send a pong frame.
-- @function connection:send_pong
-- @tparam[opt] string data Payload.
-- @treturn integer bytes Bytes sent.
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
function methods:send_pong(data)
    return self:send_frame(true, 0xa, data)
end

--- End of `connection` class section.
-- @section end

local metatable = { __index = methods }

--- Upgrade an @{eco.http.server} connection to WebSocket.
--
-- This performs server-side validation of the WebSocket handshake and sends the
-- `101 Switching Protocols` response.
--
-- @function upgrade
-- @tparam connection con HTTP server connection (from @{eco.http.server}).
-- @tparam table req HTTP request table (from @{eco.http.server}).
-- @tparam[opt] WebSocketOptions opts Options.
-- @treturn connection ws WebSocket connection.
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
-- @usage
-- local websocket = require 'eco.websocket'
-- local http = require 'eco.http.server'
-- local eco = require 'eco'
--
-- local function handler(con, req)
--   if req.path == '/ws' then
--     local ws, err = websocket.upgrade(con, req, { max_payload_len = 65535 })
--     if not ws then return nil, err end
--     local data, typ = ws:recv_frame()
--     if typ == 'ping' then ws:send_pong(data) end
--   end
-- end
--
-- eco.run(function()
--     assert(http.listen(nil, 8080, { reuseaddr = true }, handler))
-- end)
--
-- eco.loop()
function M.upgrade(con, req, opts)
    local resp = con.resp

    if req.major_version ~= 1 or req.minor_version ~= 1 then
        return nil, 'bad http version'
    end

    if resp.head_sent then
        return nil, 'response header already sent'
    end

    local ok, err = con:discard_body()
    if not ok then
        return  nil, err
    end

    local headers = req.headers

    local val = headers.upgrade
    if not val then
        return nil, 'not found "upgrade" request header'
    elseif str_lower(val) ~= 'websocket' then
        return nil, 'bad "upgrade" request header:' .. val
    end

    val = headers.connection
    if not val then
        return nil, 'not found "connection" request header'
    elseif str_lower(val) ~= 'upgrade' then
        return nil, 'bad "connection" request header: ' .. val
    end

    val = headers['sec-websocket-version']
    if not val then
        return nil, 'not found "sec-websocket-version" request header'
    elseif val ~= '13' then
        return nil, 'bad "sec-websocket-version" request header: ' .. val
    end

    local key = headers['sec-websocket-key']
    if not val then
        return nil, 'not found "sec-websocket-key" request header'
    end

    local protocol = headers['sec-websocket-protocol']

    con:set_status(101)
    con:add_header('upgrade', 'websocket')
    con:add_header('connection', 'upgrade')

    if protocol then
        con:add_header('sec-websocket-protocol', protocol)
    end

    local hash = sha1.sum(key .. '258EAFA5-E914-47DA-95CA-C5AB0DC85B11')
    con:add_header('sec-websocket-accept', base64.encode(hash))

    ok, err = con:flush()
    if not ok then
        return nil, err
    end

    opts = opts or {}

    opts.max_payload_len = opts.max_payload_len or 65535

    return setmetatable({
        b = bufio.new(con.sock),
        sock = con.sock,
        opts = opts
    }, metatable)
end

--- Connect to a WebSocket server.
--
-- This performs an HTTP upgrade handshake for `ws://` or `wss://` URIs and
-- returns a WebSocket connection on success.
--
-- @function connect
-- @tparam string uri WebSocket URI.
-- @tparam[opt] ConnectOptions opts Options.
-- @treturn connection ws WebSocket connection.
-- @treturn[2] nil On failure.
-- @treturn[2] string err Error message.
-- @usage
-- local websocket = require 'eco.websocket'
-- local eco = require 'eco'
--
-- eco.run(function()
--     local ws, err = websocket.connect('ws://127.0.0.1:8080/ws')
--     assert(ws, err)
--     ws:send_text('hello')
-- end)
--
-- eco.loop()
function M.connect(uri, opts)
    opts = opts or {}

    local headers = opts.headers or {}

    local protos = opts.protocols
    if protos then
        if type(protos) == 'table' then
            headers['sec-websocket-protocol'] = concat(protos, ',')
        else
            headers['sec-websocket-protocol'] = protos
        end
    end


    local origin = opts.origin
    if origin then
        headers['origin'] = origin
    end

    local hc = http.new()

    local res, err = hc:request('GET', uri, nil, {
        insecure = opts.insecure,
        timeout = opts.insecure,
        headers = headers
    })
    if not res then
        return nil, err
    end

    if res.code ~= 101 then
        hc:close()
        return nil, 'connect fail with status code: ' .. res.code
    end

    opts.max_payload_len = opts.max_payload_len or 65535

    local sock = hc:sock()

    return setmetatable({
        b = bufio.new(sock),
        masking = true,
        hc = hc,
        sock = sock,
        opts = opts
    }, metatable)
end

return M
