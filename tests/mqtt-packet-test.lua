#!/usr/bin/env eco

local SENTINEL = {}

local function restore_modules(saved)
    for name, value in pairs(saved) do
        if value == SENTINEL then
            package.loaded[name] = nil
        else
            package.loaded[name] = value
        end
    end
end

local function fake_timer()
    return {
        set = function(self, timeout)
            self.timeout = timeout
        end,
        cancel = function(self)
            self.cancelled = true
        end
    }
end

local function with_mqtt_socket(socket_module, fn)
    local names = {
        'eco.mqtt',
        'eco.socket',
        'eco.time'
    }
    local saved = {}

    for _, name in ipairs(names) do
        if package.loaded[name] == nil then
            saved[name] = SENTINEL
        else
            saved[name] = package.loaded[name]
        end
    end

    package.loaded['eco.socket'] = socket_module
    package.loaded['eco.time'] = {
        timer = function()
            return fake_timer()
        end
    }
    package.loaded['eco.mqtt'] = nil

    local ok, mqtt_or_err = pcall(require, 'eco.mqtt')
    if not ok then
        restore_modules(saved)
        error(mqtt_or_err)
    end

    local run_ok, run_err = pcall(fn, mqtt_or_err)

    restore_modules(saved)

    assert(run_ok, run_err)
end

local function with_mqtt(sock, fn)
    return with_mqtt_socket({
        connect_tcp = function()
            return sock
        end
    }, fn)
end

local function make_socket(input)
    local sock = {
        input = input,
        pos = 1,
        sent = {}
    }

    function sock:send(data)
        self.sent[#self.sent + 1] = data
        return #data
    end

    function sock:read(n)
        if self.pos > #self.input then
            return nil, 'closed'
        end

        local data = self.input:sub(self.pos, self.pos + n - 1)
        self.pos = self.pos + #data
        return data
    end

    function sock:readfull(n)
        if #self.input - self.pos + 1 < n then
            return nil, 'closed'
        end

        return self:read(n)
    end

    function sock:close()
        self.closed = true
    end

    return sock
end

local function encode_remaining_length(len)
    local buf = {}

    repeat
        local byte = len % 128
        len = len // 128

        if len > 0 then
            byte = byte | 0x80
        end

        buf[#buf + 1] = string.char(byte)
    until len == 0

    return table.concat(buf)
end

local function packet(typ, flags, data)
    data = data or ''
    return string.char((typ << 4) | flags) .. encode_remaining_length(#data) .. data
end

local function u16(n)
    return string.char(n >> 8, n & 0xff)
end

local CONNACK_OK = packet(2, 0x00, string.char(0x00, 0x00))

local function run_input(input)
    local sock = make_socket(input)
    local errors = {}

    with_mqtt(sock, function(mqtt)
        local client = mqtt.new({
            id = 'mqtt-packet-test',
            keepalive = 5
        })

        client:on('error', function(err, self)
            assert(self == client)
            errors[#errors + 1] = err
        end)

        client:run()
    end)

    return errors, sock
end

local function expect_malformed(input, expected)
    local errors, sock = run_input(input)
    local err = errors[1]

    assert(type(err) == 'string' and err:find(expected, 1, true),
           string.format('expected error containing %q, got %q', expected, tostring(err)))
    assert(sock.closed == true)
end

do
    local got_error

    with_mqtt_socket({
        connect_tcp = function()
            return nil, 'connect failed'
        end
    }, function(mqtt)
        local client = mqtt.new({
            id = 'mqtt-packet-test',
            keepalive = 5
        })

        client:on('error', function(err, self)
            assert(self == client)
            got_error = err
        end)

        client:run()
    end)

    assert(got_error == 'network: connect failed')
end

do
    local mid = 1
    local sock = make_socket(CONNACK_OK .. packet(9, 0x00, u16(mid) .. string.char(0x01)))
    local got_suback = false

    with_mqtt(sock, function(mqtt)
        local client = mqtt.new({
            id = 'mqtt-packet-test',
            keepalive = 5
        })

        client:on('conack', function(_, self)
            assert(self == client)
            assert(client:subscribe('topic', mqtt.QOS1))
        end)

        client:on('suback', function(ack, self)
            assert(self == client)
            assert(type(ack.results) == 'table')
            assert(#ack.results == 1)
            assert(ack.results[1].topic == 'topic')
            assert(ack.results[1].rc == mqtt.QOS1)
            got_suback = true
            client:close()
        end)

        client:on('error', function()
        end)

        client:run()
    end)

    assert(got_suback)
    assert(sock.closed == true)
end

expect_malformed(packet(2, 0x00, string.char(0x00)),
                 'malformed CONNACK packet: remaining length must be 2')
expect_malformed(CONNACK_OK .. packet(3, 0x00, string.char(0x00)),
                 'malformed PUBLISH packet: missing topic length')
expect_malformed(CONNACK_OK .. packet(3, 0x00, u16(4) .. 'ab'),
                 'malformed PUBLISH packet: truncated topic name')
expect_malformed(CONNACK_OK .. packet(3, 0x02, u16(1) .. 't'),
                 'malformed PUBLISH packet: missing packet id')
expect_malformed(CONNACK_OK .. packet(3, 0x06, u16(1) .. 't'),
                 'malformed PUBLISH packet: invalid qos')
expect_malformed(CONNACK_OK .. packet(4, 0x00, string.char(0x00)),
                 'malformed PUBACK packet: remaining length must be 2')
expect_malformed(CONNACK_OK .. packet(6, 0x00, u16(1)),
                 'malformed PUBREL packet: invalid flags 0x00')
expect_malformed(CONNACK_OK .. packet(9, 0x00, u16(1)),
                 'malformed SUBACK packet: remaining length must be at least 3')
expect_malformed(CONNACK_OK .. packet(11, 0x00, ''),
                 'malformed UNSUBACK packet: remaining length must be 2')
expect_malformed(CONNACK_OK .. packet(13, 0x00, 'x'),
                 'malformed PINGRESP packet: remaining length must be 0')

print('mqtt packet tests passed')
