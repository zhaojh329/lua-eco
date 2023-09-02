-- SPDX-License-Identifier: MIT
-- Author: Jianhui Zhao <zhaojh329@gmail.com>

-- Referenced from https://github.com/openresty/lua-resty-websocket

local base64 = require 'eco.encoding.base64'
local sha1 = require 'eco.crypto.sha1'
local http = require 'eco.http'
local url = require 'eco.url'
local sys = require 'eco.sys'

local tostring = tostring
local concat = table.concat
local rand = math.random
local str_char = string.char
local str_byte = string.byte
local str_lower = string.lower
local str_sub = string.sub
local type = type

local M = {}

local types = {
    [0x0] = 'continuation',
    [0x1] = 'text',
    [0x2] = 'binary',
    [0x8] = 'close',
    [0x9] = 'ping',
    [0xa] = 'pong',
}

local methods = {}

function  methods:recv_frame(timeout)
    local mt = getmetatable(self)
    local sock = mt.sock
    local opts = mt.opts

    local data, err = sock:recvfull(2, timeout)
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
        data, err = sock:recvfull(2, timeout)
        if not data then
            return nil, nil, 'failed to receive the 2 byte payload length: ' .. err
        end

        payload_len = string.unpack('>I2', data)

    elseif payload_len == 127 then
        data, err = sock:recvfull(8, timeout)
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
        timeout = 10
        data, err = sock:recvfull(rest, timeout)
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

function methods:send_frame(fin, opcode, payload)
    local mt = getmetatable(self)
    local sock = mt.sock
    local opts = mt.opts

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

    local frame, err = build_frame(fin, opcode, payload_len, payload, mt.masking)
    if not frame then
        return nil, 'failed to build frame: ' .. err
    end

    local bytes, err = sock:send(frame)
    if not bytes then
        return nil, 'failed to send frame: ' .. err
    end
    return bytes
end

function methods:send_text(data)
    return self:send_frame(true, 0x1, data)
end

function methods:send_binary(data)
    return self:send_frame(true, 0x2, data)
end

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

function methods:send_ping(data)
    return self:send_frame(true, 0x9, data)
end


function methods:send_pong(data)
    return self:send_frame(true, 0xa, data)
end

function M.upgrade(con, req, opts)
    local mt = getmetatable(con)
    local resp = mt.resp

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
        return nil, 'bad "upgrade" request header: ' .. val
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

    con:set_status(http.STATUS_SWITCHING_PROTOCOLS)
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

    return setmetatable({}, {
        __index = methods,
        sock = mt.sock,
        opts = opts
    })
end

function M.connect(uri, opts)
    local u, err = url.parse(uri)
    if not u then
        return nil, err
    end

    local scheme, host, port, path = u.scheme, u.host, u.port, u.raw_path

    if scheme ~= 'ws' and scheme ~= 'wss' then
        return nil, 'unsupported scheme: ' .. scheme
    end

    opts = opts or {}

    local proto_header, origin_header

    local protos = opts.protocols
    if protos then
        if type(protos) == 'table' then
            proto_header = 'Sec-WebSocket-Protocol: ' .. concat(protos, ',') .. '\r\n'

        else
            proto_header = 'Sec-WebSocket-Protocol: ' .. protos .. '\r\n'
        end
    end

    local origin = opts.origin
    if origin then
        origin_header = 'Origin: ' .. origin .. '\r\n'
    end

    local host_header = 'Host: ' .. host

    if port ~= 80 and port ~= 443 then
        host_header = host_header .. ':' .. port
    end

    local bytes = str_char(rand(256) - 1, rand(256) - 1, rand(256) - 1,
                           rand(256) - 1, rand(256) - 1, rand(256) - 1,
                           rand(256) - 1, rand(256) - 1, rand(256) - 1,
                           rand(256) - 1, rand(256) - 1, rand(256) - 1,
                           rand(256) - 1, rand(256) - 1, rand(256) - 1,
                           rand(256) - 1)

    local key = base64.encode(bytes)
    local head = {
        'GET ' .. path .. ' HTTP/1.1\r\n',
        'Upgrade: websocket\r\n',
        host_header .. '\r\n',
        'Sec-WebSocket-Key: ' .. key .. '\r\n',
        proto_header or '',
        'Sec-WebSocket-Version: 13\r\n',
        origin_header or '',
        'Connection: Upgrade\r\n'
    }

    for k, v in pairs(opts.headers or {}) do
        head[#head + 1] = k .. ': ' .. v .. '\r\n'
    end

    local sock, err = http.connect(host, port, scheme == 'wss', opts)
    if not sock then
        return nil, 'connect fail: ' .. err
    end

    bytes, err = sock:send(concat(head) .. '\r\n')
    if not bytes then
        sock:close()
        return nil, 'failed to send the handshake request: ' .. err
    end

    local timeout = opts.timeout or 30
    local deadtime = sys.uptime() + timeout

    local line, err = sock:recv('*l', deadtime - sys.uptime())
    if not line then
        return nil, err
    end

    local code, status = line:match('^HTTP/1.1%s*(%d+)%s*(.*)')
    if not code or not status then
        sock:close()
        return nil, 'invalid http status line'
    end

    if code ~= '101' then
        sock:close()
        return nil, 'connect fail with status code: ' .. code
    end

    while true do
        line, err = sock:recv('*l', deadtime - sys.uptime())
        if not line then
            sock:close()
            return nil, 'failed to receive response header: ' .. err
        end

        if line == '' then
            break
        end
    end

    opts.max_payload_len = opts.max_payload_len or 65535

    return setmetatable({}, {
        __index = methods,
        masking = true,
        sock = sock,
        opts = opts
    })
end

return M
