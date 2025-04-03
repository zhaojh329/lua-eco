-- SPDX-License-Identifier: MIT
-- Author: Jianhui Zhao <zhaojh329@gmail.com>

local socket = require 'eco.socket'
local time = require 'eco.time'

local str_char = string.char
local str_byte = string.byte
local concat = table.concat

local M = {
    QOS0 = 0,
    QOS1 = 1,
    QOS2 = 2,
    SUBACK_FAILURE = 0x80,
    CONNACK_ACCEPTED = 0,
    CONNACK_REFUSED_PROTOCOL_VERSION = 1,
    CONNACK_REFUSED_IDENTIFIER_REJECTED = 2,
    CONNACK_REFUSED_SERVER_UNAVAILABLE = 3,
    CONNACK_REFUSED_BAD_USER_NAME_OR_PASSWORD = 4,
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
local PKT_DISCONNECT  = 14

local retransmit_interval = 3.0
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
        assert(value == nil or type(value) == 'number', 'expecting port to be a number')
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
        assert(value == nil or type(value) == 'number', 'expecting mark to be a number')
    elseif name == 'device' then
        assert(value == nil or type(value) == 'string', 'expecting device to be a string')
    elseif name == 'id' then
        assert(value == nil or type(value) == 'string', 'expecting id to be a string')
    elseif name == 'keepalive' then
        assert(value == nil or type(value) == 'number', 'expecting keepalive to be a number')
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

    return setmetatable({ buf = buf }, pkt_metatable)
end

local function get_next_mid(self)
    self.mid = self.mid + 1

    if self.mid > 0xffff then
        self.mid = 1
    end

    return self.mid
end

local function on_event(self, ev, data)
    local cb = self.handlers[ev]
    if cb then
        cb(data, self)
    end
end

local function send_pkt(self, data)
    local ok, err = self.sock:send(data)
    if not ok then
        return nil, 'network: ' .. err
    end

    return ok
end

local function handle_retransmit(tmr, self)
    for _, w in pairs(self.wait_for_suback) do
        send_pkt(self, w.data)
    end

    for _, w in pairs(self.wait_for_unsuback) do
        send_pkt(self, w.data)
    end

    for _, w in pairs(self.wait_for_puback) do
        send_pkt(self, w.data)
    end

    for _, w in pairs(self.wait_for_pubrec) do
        send_pkt(self, w.data)
    end

    tmr:set(retransmit_interval)
end

local max_mult = 128 * 128 * 128

local function read_packet(sock)
    local byte, err = sock:read(1, read_timeout)
    if not byte then
        if err ~= 'timeout' then
            err = 'network: ' .. err
        end
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

    local data, err = sock:readfull(remlen, read_timeout)
    if not data then
        return nil, 'network: ' .. err
    end

    return typ, flags, data
end

local function handle_packet(self)
    local pt, flags, data = read_packet(self.sock)
    if not pt then
        local err = flags
        if err ~= 'timeout' then
            return false, err
        end

        if not self.connected then
            return false, 'wait CONACK timeout'
        elseif self.wait_pingresp and time.now() -  self.wait_pingresp >= read_timeout then
            return false, 'wait PINGRESP timeout'
        end

        return true
    end

    self.wait_pingresp = nil

    if not self.connected and pt ~= PKT_CONNACK then
        return false, 'expecting CONNACK but received ' .. pt
    end

    if pt == PKT_CONNACK then
        if self.connected then
            on_event(self, 'error', 'unexpecting CONNACK received')
            return true
        end

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

            self.retransmit_timer:set(retransmit_interval)

            if opts.keepalive > 0 then
                self.ping_tmr:set(opts.keepalive)
            end
        end

        on_event(self, 'conack', { rc = rc, reason = reason, session_present = session_present })
    elseif pt == PKT_SUBACK then
        local mid, rc = string.unpack('>I2B', data)
        local w = self.wait_for_suback[mid]
        if not w then
            return true
        end

        self.wait_for_suback[mid] = nil

        if rc ~= M.QOS0 and rc ~= M.QOS1 and rc ~= M.QOS2 and rc ~= M.SUBACK_FAILURE then
            on_event(self, 'error', 'SUBACK for topic "' .. w.topic .. '" with invalid return code ' .. rc)
        else
            on_event(self, 'suback', { rc = rc, topic = w.topic })
        end
    elseif pt == PKT_UNSUBACK then
        local mid = string.unpack('>I2', data)
        local w = self.wait_for_unsuback[mid]
        if not w then
            return true
        end
        self.wait_for_unsuback[mid] = nil
        on_event(self, 'unsuback', w.topic)
    elseif pt == PKT_PUBACK then
        local mid = string.unpack('>I2', data)
        local w = self.wait_for_puback[mid]
        if not w then
            return true
        end
        self.wait_for_puback[mid] = nil
        return true
    elseif pt == PKT_PUBREC then
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

        data = mqtt_packet(PKT_PUBREL, 0x02, 2):add_u16(mid):data()
        self.wait_for_pubcomp[mid] = { data = data }
        return send_pkt(self, data)
    elseif pt == PKT_PUBCOMP then
        local mid = string.unpack('>I2', data)
        local w = self.wait_for_pubcomp[mid]
        if not w then
            return true
        end
        self.wait_for_pubcomp[mid] = nil
    elseif pt == PKT_PUBREL then
        local mid = string.unpack('>I2', data)
        local w = self.wait_for_pubrel[mid]
        if not w then
            return true
        end
        self.wait_for_pubrel[mid] = nil
        data = mqtt_packet(PKT_PUBCOMP, 0x02, 2):add_u16(mid):data()
        return send_pkt(self, data)
    elseif pt == PKT_PUBLISH then
        local topic_len = string.unpack('>I2', data)
        local topic = data:sub(3, 3 + topic_len - 1)
        local dup = (flags >> 3) & 0x1 == 0x1
        local qos = (flags >> 1) & 0x3
        local retain = flags & 0x1 == 0x1

        data = data:sub(3 + topic_len)

        if qos > 0 then
            local mid = string.unpack('>I2', data)

            if qos == M.QOS1 then
                local ok, err = send_pkt(self, mqtt_packet(PKT_PUBACK, 0x02, 2):add_u16(mid):data())
                if not ok then
                    return false, err
                end
            elseif qos == M.QOS2 then
                -- check if this is a duplicate
                local w = self.wait_for_pubrel[mid]
                if w then
                    return true
                else
                    local pkt = mqtt_packet(PKT_PUBREC, 0x02, 2):add_u16(mid)
                    self.wait_for_pubrel[mid] = { data = pkt:data() }
                    local ok, err = send_pkt(self, pkt:data())
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
    end

    return true
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
    opts.keepalive = opts.keepalive or 30.0

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

    return send_pkt(self, pkt:data())
end

local methods = {}

function methods:publish(topic, payload, qos, retain)
    assert(type(topic) == 'string')
    assert(type(payload) == 'string')
    assert(retain == nil or type(retain) == 'boolean')

    if not self.connected then
        return false, 'unconnected'
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

    local data = pkt:data()

    if qos > 0 then
        -- set dup flag
        pkt:change_flags(flags | 1 << 3)

        if qos == M.QOS1 then
            self.wait_for_puback[mid] = { data = pkt:data() }
        else
            self.wait_for_pubrec[mid] = { data = pkt:data() }
        end
    end

    local ok, err = send_pkt(self, data)
    if not ok then
        if qos > 0 then
            if qos == M.QOS1 then
                self.wait_for_puback[mid] = nil
            else
                self.wait_for_pubrec[mid] = nil
            end
        end

        return false, err
    end

    return true
end

function methods:subscribe(topic, qos)
    assert(type(topic) == 'string' and #topic > 0)
    assert(qos == nil or qos == M.QOS0 or qos == M.QOS1 or qos == M.QOS2)

    if not self.connected then
        return false, 'unconnected'
    end

    local remlen = 2 + 2 + #topic + 1

    local mid = get_next_mid(self)
    local pkt = mqtt_packet(PKT_SUBSCRIBE, 0x02, remlen):add_u16(mid)

    pkt:add_string(topic)
    pkt:add_u8(qos or M.QOS0)

    local data = pkt:data()

    self.wait_for_suback[mid] = {
        topic = topic,
        data = data
    }

    local ok, err = send_pkt(self, data)
    if not ok then
        self.wait_for_suback[mid] = nil
        return false, err
    end

    return true
end

function methods:unsubscribe(topic)
    assert(type(topic) == 'string' and #topic > 0)

    if not self.connected then
        return false, 'unconnected'
    end

    local remlen = 2 + 2 + #topic

    local mid = get_next_mid(self)
    local pkt = mqtt_packet(PKT_UNSUBSCRIBE, 0x02, remlen):add_u16(mid)

    pkt:add_string(topic)

    local data = pkt:data()

    self.wait_for_unsuback[mid] = {
        topic = topic,
        data = data
    }

    local ok, err = send_pkt(self, data)
    if not ok then
        self.wait_for_unsuback[mid] = nil
        return false, err
    end

    return true
end

function methods:disconnect()
    if not self.connected then
        return true
    end

    local pkt = mqtt_packet(PKT_DISCONNECT)
    return send_pkt(self, pkt:data())
end

-- Add functions as handlers of given events
-- client:on(event, function)
-- client:on({ event1 = func1, event2 = func2 })
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

function methods:set(name, value)
    local opts = self.opts
    check_option(name, value)
    opts[name] = value
end

-- Start handling events until the network connection is closed
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

    self.retransmit_timer:cancel()
    self.ping_tmr:cancel()
    self.sock:close()
    self.wait_pingresp = nil
    self.connected = false
end

local metatable = {
    __index = methods
}

--[[
    opts: A table contains some options:
        ipaddr: Network address to connect to. Defaults to '127.0.0.1'.
        port: Network port to connect to. Defaults to 1883 for plain MQTT and 8883 for MQTT over TLS.
        ssl: A boolean, indicates connecting with SSL/TLS.
        ca: CA certificate for authentication if required by server.
        cert: Client certificate for authentication, if required by server.
        key: Client private key for authentication, if required by server.
        insecure: A boolean, SSL connecting with insecure.
        mark: A number used to set SO_MARK to socket.
        device: A string used to set SO_BINDTODEVICE to socket.

        id: client id, will be randomly generated if not provided.
        keepalive: Keep alive in sesonds, defaults 30.
        clean_session: A boolean
        will: A table contains some options for will:
            topic: The topic name of client's will message.
            message: The message to be published when the client disconnected.
            qos: The qos used to published will message.
            retain: Retain will message.
        username: The username to be used to connect to the broker with.
        password: The password to be used to connect to the broker with.
--]]
function M.new(opts)
    opts = opts or {}

    assert(type(opts) == 'table', 'expecting opts to be a table')

    for name, value in pairs(opts) do
        check_option(name, value)
        opts[name] = value
    end

    local o = {
        mid = 0,
        opts = opts,
        handlers = {},
        wait_for_suback = {},
        wait_for_unsuback = {},
        wait_for_puback = {},
        wait_for_pubrec = {},
        wait_for_pubrel = {},
        wait_for_pubcomp = {}
    }

    o.retransmit_timer = time.timer(handle_retransmit, o)

    o.ping_tmr = time.timer(function(tmr)
        o.wait_pingresp = time.now()

        local ok, err = send_pkt(o, mqtt_packet(PKT_PINGREQ):data())
        if not ok then
            on_event(o, 'error', err)
        else
            tmr:set(o.opts.keepalive)
        end
    end)

    return setmetatable(o, metatable)
end

return M
