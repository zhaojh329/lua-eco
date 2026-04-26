-- SPDX-License-Identifier: MIT
-- Author: Jianhui Zhao <zhaojh329@gmail.com>

--- MQTT 3.1.1 client.
--
-- This module implements a small MQTT client that integrates with lua-eco's
-- coroutine scheduler.
--
-- Create a client with `new`, register event handlers with `client:on`, then
-- call `client:run` to connect and start processing packets.
--
-- Events are delivered via callbacks registered by `client:on`. A handler is
-- called as `handler(data, client)`.
--
-- Known events:
--
-- - `conack`: CONNACK received. `data = { rc = integer, reason = string, session_present = boolean }`
-- - `suback`: SUBACK received. `data = { rc = integer, topic = string }`
-- - `unsuback`: UNSUBACK received. `data = topic` (string)
-- - `publish`: PUBLISH received. `data = { topic = string, payload = string, qos = integer, dup = boolean, retain = boolean }`
-- - `error`: network/protocol errors and timeouts. `data = err` (string)
--
-- @module eco.mqtt

local socket = require 'eco.socket'
local time = require 'eco.time'

local str_char = string.char
local str_byte = string.byte
local concat = table.concat

local M = {
    --- QoS 0: at most once.
    QOS0 = 0,
    --- QoS 1: at least once.
    QOS1 = 1,
    --- QoS 2: exactly once.
    QOS2 = 2,

    --- SUBACK failure return code.
    SUBACK_FAILURE = 0x80,

    --- CONNACK return code: connection accepted.
    CONNACK_ACCEPTED = 0,
    --- CONNACK return code: unacceptable protocol version.
    CONNACK_REFUSED_PROTOCOL_VERSION = 1,
    --- CONNACK return code: identifier rejected.
    CONNACK_REFUSED_IDENTIFIER_REJECTED = 2,
    --- CONNACK return code: server unavailable.
    CONNACK_REFUSED_SERVER_UNAVAILABLE = 3,
    --- CONNACK return code: bad username or password.
    CONNACK_REFUSED_BAD_USER_NAME_OR_PASSWORD = 4,
    --- CONNACK return code: not authorized.
    CONNACK_REFUSED_NOT_AUTHORIZED = 5
}

local PKT_CONNECT     = 1
local PKT_CONNACK     = 2
local PKT_PUBLISH     = 3
local PKT_PUBACK      = 4
local PKT_PUBREC      = 5
local PKT_PUBREL      = 6
local PKT_PUBCOMP     = 7
local PKT_SUBSCRIBE   = 8
local PKT_SUBACK      = 9
local PKT_UNSUBSCRIBE = 10
local PKT_UNSUBACK    = 11
local PKT_PINGREQ     = 12
local PKT_PINGRESP    = 13
local PKT_DISCONNECT  = 14

local read_timeout = 5.0

local function check_will_option(will)
    assert(type(will.topic) == 'string', 'expecting will.topic to be a string')
    assert(type(will.message) == 'string', 'expecting will.message to be a string')
    assert(will.retain == nil or type(will.retain) == 'boolean', 'expecting will.retain to be a boolean')

    if will.qos ~= nil then
        assert(will.qos == M.QOS0 or will.qos == M.QOS1 or will.qos == M.QOS2, 'expecting will.qos to be 0 or 1 or 2')
    end
end

local function check_option(name, value)
    assert(type(name) == 'string')

    if name == 'ipaddr' then
        assert(value == nil or type(value) == 'string', 'expecting ipaddr to be a string')
    elseif name == 'port' then
        assert(value == nil or math.type(value) == 'integer', 'expecting port to be an integer')
    elseif name == 'ssl' then
        assert(value == nil or type(value) == 'boolean', 'expecting ssl to be a boolean')
    elseif name == 'ca' then
        assert(value == nil or type(value) == 'string', 'expecting ca to be a string')
    elseif name == 'cert' then
        assert(value == nil or type(value) == 'string', 'expecting cert to be a string')
    elseif name == 'key' then
        assert(value == nil or type(value) == 'string', 'expecting key to be a string')
    elseif name == 'insecure' then
        assert(value == nil or type(value) == 'boolean', 'expecting insecure to be a boolean')
    elseif name == 'mark' then
        assert(value == nil or math.type(value) == 'integer', 'expecting mark to be an integer')
    elseif name == 'device' then
        assert(value == nil or type(value) == 'string', 'expecting device to be a string')
    elseif name == 'id' then
        assert(value == nil or type(value) == 'string', 'expecting id to be a string')
    elseif name == 'keepalive' then
        assert(value == nil or math.type(value) == 'integer', 'expecting keepalive to be an integer')
        assert(value == nil or value >= 5, 'keepalive cannot be less than 5')
    elseif name == 'clean_session' then
        assert(value == nil or type(value) == 'boolean', 'expecting clean_session to be a boolean')
    elseif name == 'username' then
        assert(value == nil or type(value) == 'string', 'expecting username to be a string')
    elseif name == 'password' then
        assert(value == nil or type(value) == 'string', 'expecting password to be a string')
    elseif name == 'will' then
        assert(value == nil or type(value) == 'table', 'expecting will to be a table')
        check_will_option(value)
    end
end

local pkt_methods = {}

function pkt_methods:change_flags(flags)
    local buf = self.buf
    local byte = str_byte(buf[1])
    self.buf[1] = str_char((byte & 0xf0) | flags)
    return self
end

function pkt_methods:add_u16(n)
    local buf = self.buf
    buf[#buf + 1] = string.char(n >> 8, n & 0xff)
    return self
end

function pkt_methods:add_u8(n)
    local buf = self.buf
    buf[#buf + 1] = string.char(n)
    return self
end

function pkt_methods:add_string(s)
    local buf = self.buf
    buf[#buf + 1] = string.char(#s >> 8, #s & 0xff)
    buf[#buf + 1] = s
    return self
end

function pkt_methods:add_data(data)
    local buf = self.buf
    buf[#buf + 1] = data
    return self
end

function pkt_methods:data()
    return concat(self.buf)
end

local pkt_metatable = {
    __index = pkt_methods
}

local function mqtt_packet(typ, flags, remlen)
    flags = flags or 0
    remlen = remlen or 0

    local buf = { str_char(typ << 4 | flags) }

    repeat
        local byte = remlen % 128

        remlen = remlen // 128

        if remlen > 0 then
            byte = byte | 128
        end

        buf[#buf + 1] = str_char(byte)
    until remlen == 0

    return setmetatable({ type = typ, buf = buf }, pkt_metatable)
end

local function get_next_mid(self)
    self.mid = self.mid + 1

    if self.mid > 0xffff then
        self.mid = 1
    end

    return self.mid
end

local function get_next_tx_seq(self)
    self.tx_seq = self.tx_seq + 1
    return self.tx_seq
end

local function on_event(self, ev, data)
    local cb = self.handlers[ev]
    if cb then
        cb(data, self)
    end
end

local function send_pkt(self, pkt)
    local ok, err = self.sock:send(pkt:data())
    if not ok then
        return nil, 'network: ' .. err
    end

    if pkt.type ~= PKT_DISCONNECT then
        self.ping_tmr:set(self.opts.keepalive)
    end

    return ok
end

local function retransmit_unack_packets(self)
    local packets = {}

    local function add_waiting_packets(waiting)
        for _, w in pairs(waiting) do
            packets[#packets + 1] = w
        end
    end

    add_waiting_packets(self.wait_for_puback)
    add_waiting_packets(self.wait_for_pubrec)
    add_waiting_packets(self.wait_for_pubcomp)

    table.sort(packets, function(a, b)
        return a.seq < b.seq
    end)

    for _, w in ipairs(packets) do
        local ok, err = send_pkt(self, w.pkt)
        if not ok then
            return nil, err
        end
    end

    return true
end

local max_mult = 128 * 128 * 128 * 128

local function read_packet(sock)
    local byte, err = sock:read(1)
    if not byte then
        return nil, err
    end

    byte = str_byte(byte)

    local typ = byte >> 4
    local flags = byte & 0xf

    local remlen = 0
    local mult = 1

    repeat
        byte, err = sock:read(1, read_timeout)
        if not byte then
            return nil, 'network: ' .. err
        end

        byte = str_byte(byte)
        remlen = remlen + mult * (byte & 0x7f)
        mult = mult * 128

        if mult > max_mult then
            return nil, 'malformed remaining length'
        end
    until byte & 0x80 == 0

    if remlen == 0 then
        return typ, flags, ''
    end

    local data, err = sock:readfull(remlen, read_timeout)
    if not data then
        return nil, 'network: ' .. err
    end

    return typ, flags, data
end

local function handle_conack(self, flags, data)
    if self.connected then
        on_event(self, 'error', 'unexpecting CONNACK received')
        return true
    end

    self.wait_conack:cancel()

    local reasons = {
        'connection accepted',
        'connection refused: unacceptable protocol version',
        'connection refused: identifier rejected',
        'connection refused: server unavailable',
        'connection refused: bad user name or password',
        'connection refused: not authorised'
    }

    local rc = str_byte(data, 2)
    local reason = reasons[rc + 1] or ('connection refused: unknown reason code ' .. rc)
    local session_present = str_byte(data) & 0x01 == 1

    if rc == M.CONNACK_ACCEPTED then
        local opts = self.opts

        self.connected = true

        if not opts.clean_session and session_present then
            local ok, retransmit_err = retransmit_unack_packets(self)
            if not ok then
                return false, retransmit_err
            end
        end

        if opts.keepalive > 0 then
            self.ping_tmr:set(opts.keepalive)
        end
    end

    on_event(self, 'conack', { rc = rc, reason = reason, session_present = session_present })

    return true
end

local function handle_publish(self, flags, data)
    local topic_len = string.unpack('>I2', data)
    local topic = data:sub(3, 3 + topic_len - 1)
    local dup = (flags >> 3) & 0x1 == 0x1
    local qos = (flags >> 1) & 0x3
    local retain = flags & 0x1 == 0x1

    data = data:sub(3 + topic_len)

    if qos > 0 then
        local mid = string.unpack('>I2', data)

        if qos == M.QOS1 then
            local pkt = mqtt_packet(PKT_PUBACK, 0x00, 2):add_u16(mid)
            local ok, err = send_pkt(self, pkt)
            if not ok then
                return false, err
            end
        elseif qos == M.QOS2 then
            -- check if this is a duplicate
            local w = self.wait_for_pubrel[mid]
            if w then
                return true
            else
                local pkt = mqtt_packet(PKT_PUBREC, 0x00, 2):add_u16(mid)
                self.wait_for_pubrel[mid] = { pkt = pkt }
                local ok, err = send_pkt(self, pkt)
                if not ok then
                    return false, err
                end
            end
        else
            on_event(self, 'error', 'invalid PUBLISH received with unknown qos number ' .. qos)
            return true
        end

        data = data:sub(3)
    end

    on_event(self, 'publish', { topic = topic, payload = data, qos = qos, dup = dup, retain = retain })

    return true
end

local function handle_puback(self, flags, data)
    local mid = string.unpack('>I2', data)
    local w = self.wait_for_puback[mid]
    if not w then
        return true
    end
    self.wait_for_puback[mid] = nil
    return true
end

local function handle_pubrec(self, flags, data)
    local mid = string.unpack('>I2', data)

    -- check if this is a duplicate
    if self.wait_for_pubcomp[mid] then
        return true
    end

    local w = self.wait_for_pubrec[mid]
    if not w then
        return true
    end
    self.wait_for_pubrec[mid] = nil

    local pkt = mqtt_packet(PKT_PUBREL, 0x02, 2):add_u16(mid)
    self.wait_for_pubcomp[mid] = {
        pkt = pkt,
        seq = get_next_tx_seq(self)
    }
    return send_pkt(self, pkt)
end

local function handle_pubrel(self, flags, data)
    local mid = string.unpack('>I2', data)
    self.wait_for_pubrel[mid] = nil
    local pkt = mqtt_packet(PKT_PUBCOMP, 0x00, 2):add_u16(mid)
    return send_pkt(self, pkt)
end

local function handle_pubcomp(self, flags, data)
    local mid = string.unpack('>I2', data)
    local w = self.wait_for_pubcomp[mid]
    if not w then
        return true
    end
    self.wait_for_pubcomp[mid] = nil
    return true
end

local function handle_suback(self, flags, data)
    local mid = string.unpack('>I2', data)
    local w = self.wait_for_suback[mid]
    if not w then
        return true
    end

    self.wait_for_suback[mid] = nil

    local suback_count = #data - 2
    local topic_count = #w.topics

    if suback_count ~= topic_count then
        on_event(self, 'error',
            'SUBACK return code count mismatch: expecting ' .. topic_count .. ', got ' .. suback_count)
        return true
    end

    for i = 1, topic_count do
        local rc = str_byte(data, 2 + i)
        local topic = w.topics[i].topic

        if rc ~= M.QOS0 and rc ~= M.QOS1 and rc ~= M.QOS2 and rc ~= M.SUBACK_FAILURE then
            on_event(self, 'error', 'SUBACK for topic "' .. topic .. '" with invalid return code ' .. rc)
            return true
        end

        on_event(self, 'suback', { rc = rc, topic = topic })
    end

    return true
end

local function handle_unsuback(self, flags, data)
    local mid = string.unpack('>I2', data)
    local w = self.wait_for_unsuback[mid]
    if not w then
        return true
    end

    self.wait_for_unsuback[mid] = nil

    for _, topic in ipairs(w.topics) do
        on_event(self, 'unsuback', topic)
    end

    return true
end

local function handle_pingresp(self, flags, data)
    return true
end

local handlers = {
    [PKT_CONNACK] = handle_conack,
    [PKT_PUBLISH] = handle_publish,
    [PKT_PUBACK] = handle_puback,
    [PKT_PUBREC] = handle_pubrec,
    [PKT_PUBREL] = handle_pubrel,
    [PKT_PUBCOMP] = handle_pubcomp,
    [PKT_SUBACK] = handle_suback,
    [PKT_UNSUBACK] = handle_unsuback,
    [PKT_PINGRESP] = handle_pingresp,
}

local function handle_packet(self)
    local pt, flags, data = read_packet(self.sock)
    if not pt then
        return false, flags
    end

    if not self.connected and pt ~= PKT_CONNACK then
        return false, 'expecting CONNACK but received ' .. pt
    end

    self.wait_pingresp:cancel()

    local handler = handlers[pt]
    if not handler then
        on_event(self, 'error', 'unknown packet type ' .. pt)
        return true
    end

    return handler(self, flags, data)
end

local function mqtt_connect(self)
    local opts = self.opts
    local ipaddr = opts.ipaddr or '127.0.0.1'
    local sock, err

    if opts.ssl then
        local ssl = require 'eco.ssl'
        sock, err = ssl.connect(ipaddr, opts.port or 8883, opts)
    else
        sock, err = socket.connect_tcp(ipaddr, opts.port or 1883, opts)
    end
    if not sock then
        return false, 'network: ' .. err
    end

    opts.id = opts.id or string.format('lua-eco-%07x', math.random(1, 0xfffffff))
    opts.keepalive = opts.keepalive or 30

    local remlen = 10 + #opts.id + 2
    local will = opts.will
    local flags = 0

    if opts.clean_session then
        flags = flags | 1 << 1
    end

    if will then
        remlen = remlen + #will.topic + 2
        remlen = remlen + #will.message + 2

        flags = flags | 1 << 2

        if will.qos then
            flags = flags | (will.qos & 0x3) << 3
        end

        if will.retain then
            flags = flags | 1 << 5
        end
    end

    if opts.username then
        remlen = remlen + #opts.username + 2
        flags = flags | 1 << 7

        if opts.password then
            remlen = remlen + #opts.password + 2
            flags = flags | 1 << 6
        end
    end

    local pkt = mqtt_packet(PKT_CONNECT, 0, remlen)

    -- Protocol Level: 3.1.1
    pkt:add_string('MQTT')
    pkt:add_u8(0x04)

    pkt:add_u8(flags)
    pkt:add_u16(opts.keepalive)
    pkt:add_string(opts.id)

    if will then
        pkt:add_string(will.topic)
        pkt:add_string(will.message)
    end

    if opts.username then
        pkt:add_string(opts.username)

        if opts.password then
            pkt:add_string(opts.password)
        end
    end

    self.sock = sock

    self.wait_conack:set(3)

    return send_pkt(self, pkt)
end

--- MQTT client object.
--
-- A client instance is created by calling @{mqtt.new}.
--
-- @type client

local methods = {}

--- Publish a message.
--
-- For QoS 1 and 2, the client will keep the packet for retransmission until
-- an acknowledgement is received.
--
-- @tparam string topic Topic name.
-- @tparam string payload Message payload.
-- @tparam[opt=mqtt.QOS0] integer qos One of @{mqtt.QOS0}, @{mqtt.QOS1}, @{mqtt.QOS2}.
-- @tparam[opt] boolean retain Set the RETAIN flag.
-- @treturn boolean true On success
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
function methods:publish(topic, payload, qos, retain)
    assert(type(topic) == 'string')
    assert(type(payload) == 'string')
    assert(retain == nil or type(retain) == 'boolean')

    if not self.connected then
        return nil, 'unconnected'
    end

    if qos ~= nil then
        assert(qos == M.QOS0 or qos == M.QOS1 or qos == M.QOS2)
    end

    local remlen = 2 + #topic + #payload

    qos = qos or M.QOS0

    if qos > 0 then
        remlen = remlen + 2
    end

    local flags = qos << 1

    if retain then
        flags = flags | 0x1
    end

    local pkt = mqtt_packet(PKT_PUBLISH, flags, remlen)

    pkt:add_string(topic)

    local mid = 0

    if qos > 0 then
        mid = get_next_mid(self)
        pkt:add_u16(mid)
    end

    pkt:add_data(payload)

    if qos > 0 then
        -- set dup flag
        pkt:change_flags(flags | 1 << 3)

        if qos == M.QOS1 then
            self.wait_for_puback[mid] = {
                pkt = pkt,
                seq = get_next_tx_seq(self)
            }
        else
            self.wait_for_pubrec[mid] = {
                pkt = pkt,
                seq = get_next_tx_seq(self)
            }
        end
    end

    local ok, err = send_pkt(self, pkt)
    if not ok then
        if qos > 0 then
            if qos == M.QOS1 then
                self.wait_for_puback[mid] = nil
            else
                self.wait_for_pubrec[mid] = nil
            end
        end

        return nil, err
    end

    return true
end

--- Subscribe to topic(s).
--
-- This sends a SUBSCRIBE packet and later triggers the `suback` event.
--
-- Arguments are accepted as `(topic, qos, topic2, qos2, ...)`, and must be in pairs.
--
-- @tparam string topic Topic filter.
-- @tparam[opt=mqtt.QOS0] integer qos Requested QoS.
-- @param ... Optional additional `(topic, qos)` pairs.
-- @treturn boolean true On success
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
function methods:subscribe(topic, qos, ...)
    assert(type(topic) == 'string' and #topic > 0, 'expecting topic to be a non-empty string')
    assert(qos == nil or qos == M.QOS0 or qos == M.QOS1 or qos == M.QOS2,
           'expecting qos to be 0 or 1 or 2')

    local extra_nargs = select('#', ...)
    assert(extra_nargs % 2 == 0, 'expecting topic and qos to appear in pairs')

    local topics = {
        {
            topic = topic,
            qos = qos
        }
    }

    for i = 1, extra_nargs, 2 do
        local t = select(i, ...)
        local q = select(i + 1, ...)
        local idx = #topics + 1

        assert(type(t) == 'string' and #t > 0,
               'expecting topic #' .. idx .. ' to be a non-empty string')
        assert(q == nil or q == M.QOS0 or q == M.QOS1 or q == M.QOS2,
               'expecting qos #' .. idx .. ' to be 0 or 1 or 2')

        topics[idx] = {
            topic = t,
            qos = q
        }
    end

    if not self.connected then
        return nil, 'unconnected'
    end

    local remlen = 2

    for _, sub in ipairs(topics) do
        remlen = remlen + 2 + #sub.topic + 1
    end

    local mid = get_next_mid(self)
    local pkt = mqtt_packet(PKT_SUBSCRIBE, 0x02, remlen):add_u16(mid)

    for _, sub in ipairs(topics) do
        pkt:add_string(sub.topic)
        pkt:add_u8(sub.qos or M.QOS0)
    end

    self.wait_for_suback[mid] = {
        topics = topics,
        pkt = pkt,
        seq = get_next_tx_seq(self)
    }

    local ok, err = send_pkt(self, pkt)
    if not ok then
        self.wait_for_suback[mid] = nil
        return nil, err
    end

    return true
end

--- Unsubscribe from topic(s).
--
-- This sends an UNSUBSCRIBE packet and later triggers the `unsuback` event.
--
-- @tparam string topic Topic filter.
-- @param ... Optional additional topic filters.
-- @treturn boolean true On success
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
function methods:unsubscribe(topic, ...)
    assert(type(topic) == 'string' and #topic > 0, 'expecting topic to be a non-empty string')

    local topics = { topic }
    local extra_nargs = select('#', ...)

    for i = 1, extra_nargs do
        local t = select(i, ...)

        assert(type(t) == 'string' and #t > 0,
               'expecting topic #' .. (#topics + 1) .. ' to be a non-empty string')

        topics[#topics + 1] = t
    end

    if not self.connected then
        return nil, 'unconnected'
    end

    local remlen = 2

    for _, t in ipairs(topics) do
        remlen = remlen + 2 + #t
    end

    local mid = get_next_mid(self)
    local pkt = mqtt_packet(PKT_UNSUBSCRIBE, 0x02, remlen):add_u16(mid)

    for _, t in ipairs(topics) do
        pkt:add_string(t)
    end

    self.wait_for_unsuback[mid] = {
        topic = topic,
        topics = topics,
        pkt = pkt,
        seq = get_next_tx_seq(self)
    }

    local ok, err = send_pkt(self, pkt)
    if not ok then
        self.wait_for_unsuback[mid] = nil
        return nil, err
    end

    return true
end

--- Send DISCONNECT.
--
-- This only sends the packet; the underlying socket is not closed here.
--
-- @treturn boolean true On success
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
function methods:disconnect()
    if not self.connected then
        return true
    end

    local pkt = mqtt_packet(PKT_DISCONNECT)
    return send_pkt(self, pkt)
end


--- Close the underlying network socket.
function methods:close()
    if self.sock then
        self.sock:close()
    end
end

--- Register event handler(s).
--
-- This function supports two calling forms:
--
-- - `client:on(event, handler)`
-- - `client:on({ event1 = handler1, event2 = handler2 })`
--
-- The handler is called as `handler(data, client)`.
--
-- @tparam string event Event name (when using the 2-argument form).
-- @tparam function handler Callback (when using the 2-argument form).
-- @tparam table handlers A table of `{ event = handler }` pairs (when using the 1-argument form).
function methods:on(...)
    local nargs = select('#', ...)
    local events

    if nargs == 2 then
        events = { [select(1, ...)] = select(2, ...) }
    elseif nargs == 1 then
        events = select(1, ...)
    else
        error('invalid args: expected only one or two arguments')
    end

    for event, func in pairs(events) do
        assert(type(event) == 'string', 'expecting event to be a string')
        assert(type(func) == 'function', 'expecting func to be a function')
        self.handlers[event] = func
    end
end

--- Set one option on the client.
--
-- This is equivalent to providing the field in @{new}'s `opts`.
--
-- @tparam string name Option name.
-- @tparam any value Option value.
function methods:set(name, value)
    local opts = self.opts
    check_option(name, value)
    opts[name] = value
end

--- Connect and start handling packets.
--
-- This call returns when the network connection is closed or an error occurs.
-- Any termination reason is reported through the `error` event.
function methods:run()
    local ok, err = mqtt_connect(self)
    if not ok then
        on_event(self, 'error', err)
        return
    end

    repeat
        ok, err = handle_packet(self)
    until not ok

    on_event(self, 'error', err)

    self.ping_tmr:cancel()
    self.wait_pingresp:cancel()
    self.sock:close()
    self.connected = false
end

--- End of `client` class section.
-- @section end

local metatable = {
    __index = methods
}

--- Create a new MQTT client.
-- @tparam[opt] table opts Options table.
-- @tparam[opt='127.0.0.1'] string opts.ipaddr Broker address.
-- @tparam[opt] int opts.port Broker port. (Default `1883` (plain) or `8883` (TLS) depending on `ssl`)
-- @tparam[opt=false] boolean opts.ssl Enable MQTT over TLS.
-- @tparam[opt] string opts.ca CA certificate path for TLS.
-- @tparam[opt] string opts.cert Client certificate path for TLS.
-- @tparam[opt] string opts.key Client private key path for TLS.
-- @tparam[opt=false] boolean opts.insecure Disable TLS certificate verification.
-- @tparam[opt] int opts.mark Set `SO_MARK` on the socket.
-- @tparam[opt] string opts.device Set `SO_BINDTODEVICE` on the socket.
-- @tparam[opt] string opts.id Client id. Randomly generated if absent.
-- @tparam[opt=30] int opts.keepalive keepalive seconds.
-- @tparam[opt=false] boolean opts.clean_session Clean session flag.
-- @tparam[opt] table opts.will Last will message: `topic` (string) `message` (string) `qos` (int)
-- @tparam[opt] string opts.username
-- @tparam[opt] string opts.password
-- @treturn client
function M.new(opts)
    opts = opts or {}

    assert(type(opts) == 'table', 'expecting opts to be a table')

    for name, value in pairs(opts) do
        check_option(name, value)
    end

    local o = {
        mid = 0,
        tx_seq = 0,
        opts = opts,
        handlers = {},
        wait_for_suback = {},
        wait_for_unsuback = {},
        wait_for_puback = {},
        wait_for_pubrec = {},
        wait_for_pubrel = {},
        wait_for_pubcomp = {}
    }

    o.wait_conack = time.timer(function()
        on_event(o, 'error', 'wait CONACK timeout')
        o:close()
    end)

    o.wait_pingresp = time.timer(function()
        on_event(o, 'error', 'wait PINGRESP timeout')
        o:close()
    end)

    o.ping_tmr = time.timer(function(tmr)
        o.wait_pingresp:set(3)

        local ok, err = send_pkt(o, mqtt_packet(PKT_PINGREQ))
        if not ok then
            o.wait_pingresp:cancel()
            on_event(o, 'error', err)
        end
    end)

    return setmetatable(o, metatable)
end

return M
