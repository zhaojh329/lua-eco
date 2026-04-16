#!/usr/bin/env eco

local eco = require 'eco'
local mqtt = require 'eco.mqtt'
local sys = require 'eco.sys'
local time = require 'eco.time'
local test = require 'test'

local function uniq(suffix)
    return string.format('%s-%d-%d', suffix, sys.getpid(), math.floor(time.now() * 1000))
end

test.run_case_sync('mqtt constants', function()
    assert(mqtt.QOS0 == 0)
    assert(mqtt.QOS1 == 1)
    assert(mqtt.QOS2 == 2)

    assert(mqtt.SUBACK_FAILURE == 0x80)

    assert(math.type(mqtt.CONNACK_ACCEPTED) == 'integer')
    assert(math.type(mqtt.CONNACK_REFUSED_PROTOCOL_VERSION) == 'integer')
    assert(math.type(mqtt.CONNACK_REFUSED_IDENTIFIER_REJECTED) == 'integer')
    assert(math.type(mqtt.CONNACK_REFUSED_SERVER_UNAVAILABLE) == 'integer')
    assert(math.type(mqtt.CONNACK_REFUSED_BAD_USER_NAME_OR_PASSWORD) == 'integer')
    assert(math.type(mqtt.CONNACK_REFUSED_NOT_AUTHORIZED) == 'integer')
end)

test.run_case_sync('mqtt new and set validations', function()
    test.expect_error_contains(function()
        mqtt.new(1)
    end, 'expecting opts to be a table')

    test.expect_error_contains(function()
        mqtt.new({ ipaddr = 1 })
    end, 'expecting ipaddr to be a string')

    test.expect_error_contains(function()
        mqtt.new({ port = 1.2 })
    end, 'expecting port to be an integer')

    test.expect_error_contains(function()
        mqtt.new({ keepalive = 4 })
    end, 'keepalive cannot be less than 5')

    test.expect_error_contains(function()
        mqtt.new({ will = 'x' })
    end, 'expecting will to be a table')

    test.expect_error_contains(function()
        mqtt.new({ will = { topic = 1, message = 'm' } })
    end, 'expecting will.topic to be a string')

    test.expect_error_contains(function()
        mqtt.new({ will = { topic = 't', message = 1 } })
    end, 'expecting will.message to be a string')

    test.expect_error_contains(function()
        mqtt.new({ will = { topic = 't', message = 'm', retain = 1 } })
    end, 'expecting will.retain to be a boolean')

    test.expect_error_contains(function()
        mqtt.new({ will = { topic = 't', message = 'm', qos = 3 } })
    end, 'expecting will.qos to be 0 or 1 or 2')

    local c = mqtt.new({
        ipaddr = '127.0.0.1',
        port = 1883,
        clean_session = true,
        keepalive = 5,
        username = 'u',
        password = 'p',
        will = { topic = 'w', message = 'x', qos = mqtt.QOS1, retain = true }
    })

    c:set('id', 'client-id')
    c:set('device', 'lo')
    c:set('mark', 0)

    test.expect_error_contains(function()
        c:set('keepalive', 3)
    end, 'keepalive cannot be less than 5')

    test.expect_error_contains(function()
        c:set('port', 1.1)
    end, 'expecting port to be an integer')
end)

test.run_case_sync('mqtt on and unconnected api semantics', function()
    local c = mqtt.new()

    test.expect_error_contains(function()
        c:on()
    end, 'invalid args: expected only one or two arguments')

    test.expect_error_contains(function()
        c:on('error', function()
        end, true)
    end, 'invalid args: expected only one or two arguments')

    test.expect_error_contains(function()
        c:on(1, function()
        end)
    end, 'expecting event to be a string')

    test.expect_error_contains(function()
        c:on('error', 1)
    end, 'expecting func to be a function')

    test.expect_error_contains(function()
        c:on({ [1] = function()
        end })
    end, 'expecting event to be a string')

    test.expect_error_contains(function()
        c:on({ error = 1 })
    end, 'expecting func to be a function')

    local called = false
    c:on('custom', function(_, self)
        assert(self == c)
        called = true
    end)

    c:on({
        error = function(err, self)
            assert(type(err) == 'string')
            assert(self == c)
        end
    })

    assert(called == false)

    test.expect_error(function()
        c:publish(1, 'x')
    end)

    test.expect_error(function()
        c:publish('t', 1)
    end)

    local qok, qerr = c:publish('t', 'x', 9)
    assert(qok == nil and qerr == 'unconnected')

    test.expect_error(function()
        c:publish('t', 'x', mqtt.QOS1, 1)
    end)

    test.expect_error(function()
        c:subscribe('', mqtt.QOS0)
    end)

    test.expect_error(function()
        c:subscribe('t', 9)
    end)

    test.expect_error(function()
        c:subscribe('t', mqtt.QOS0, 't2')
    end)

    test.expect_error(function()
        c:subscribe('t', mqtt.QOS0, '', mqtt.QOS1)
    end)

    test.expect_error(function()
        c:subscribe('t', mqtt.QOS0, 't2', 9)
    end)

    test.expect_error(function()
        c:unsubscribe('')
    end)

    test.expect_error(function()
        c:unsubscribe('t', '')
    end)

    test.expect_error(function()
        c:unsubscribe('t', 1)
    end)

    local ok, err = c:publish('t', 'x', mqtt.QOS1)
    assert(ok == nil and err == 'unconnected')

    ok, err = c:subscribe('t', mqtt.QOS1)
    assert(ok == nil and err == 'unconnected')

    ok, err = c:unsubscribe('t')
    assert(ok == nil and err == 'unconnected')

    ok, err = c:disconnect()
    assert(ok == true and err == nil)
end)

test.run_case_sync('mqtt pending queue sequence semantics', function()
    local c = mqtt.new()

    assert(c.tx_seq == 0)

    local sent = {}

    c.connected = true
    c.sock = {
        send = function(_, data)
            sent[#sent + 1] = data
            return true
        end,
        close = function()
        end
    }

    local ok, err = c:publish('seq/topic', 'q1', mqtt.QOS1)
    assert(ok and err == nil)

    local q1_mid = c.mid
    local q1 = c.wait_for_puback[q1_mid]

    assert(q1 and math.type(q1.seq) == 'integer')

    ok, err = c:publish('seq/topic', 'q2', mqtt.QOS2)
    assert(ok and err == nil)

    local q2_mid = c.mid
    local q2 = c.wait_for_pubrec[q2_mid]

    assert(q2 and q2.seq > q1.seq)

    ok, err = c:subscribe('seq/topic', mqtt.QOS1, 'seq/topic/2', mqtt.QOS2)
    assert(ok and err == nil)

    local sub_mid = c.mid
    local sub = c.wait_for_suback[sub_mid]

    assert(sub and sub.seq > q2.seq)
    assert(type(sub.topics) == 'table' and #sub.topics == 2)

    ok, err = c:unsubscribe('seq/topic', 'seq/topic/2')
    assert(ok and err == nil)

    local unsub_mid = c.mid
    local unsub = c.wait_for_unsuback[unsub_mid]

    assert(unsub and unsub.seq > sub.seq)
    assert(type(unsub.topics) == 'table' and #unsub.topics == 2)

    local before_seq = c.tx_seq

    ok, err = c:publish('seq/topic', 'q0', mqtt.QOS0)
    assert(ok and err == nil)
    assert(c.tx_seq == before_seq, 'qos0 should not enter pending retransmit queue')
    assert(c.wait_for_puback[c.mid] == nil)

    assert(#sent >= 5, 'expected sends for qos publishes and sub/unsub')
end)

local connect_failure_error

test.run_case_sync('mqtt run error path without broker', function()
    local c = mqtt.new({
        ipaddr = '127.0.0.1',
        port = 1,
        keepalive = 5,
        id = uniq('mqtt-no-broker')
    })

    local done = false

    local function finish()
        if done then
            return
        end

        done = true
        eco.unloop()
    end

    c:on('error', function(err, self)
        assert(self == c)
        assert(type(err) == 'string')
        connect_failure_error = err
        finish()
    end)

    eco.run(function()
        c:run()
        finish()
    end)

    eco.run(function()
        eco.sleep(5)
        finish()
    end)
end)

assert(type(connect_failure_error) == 'string', 'missing error callback on connect failure')
local is_network = connect_failure_error:find('network:', 1, true) ~= nil
local is_conack_timeout = connect_failure_error:find('CONACK timeout', 1, true) ~= nil
assert(is_network or is_conack_timeout,
       string.format('unexpected connect failure reason: %q', connect_failure_error))

local lifecycle = {
    done = false,
    got_conack = false,
    got_suback = false,
    got_unsuback = false,
    got_publish_q0 = false,
    got_publish_q1 = false,
    got_publish_q2 = false,
    err_reason = nil
}

test.run_case_sync('mqtt broker lifecycle semantics', function()
    local id = uniq('mqtt-full')
    local topic = 'eco/test/' .. id
    local payload_qos0 = 'q0-' .. id
    local payload_qos1 = 'q1-' .. id
    local payload_qos2 = 'q2-' .. id
    local payload_after_unsub = 'after-unsub-' .. id

    local client = mqtt.new({
        ipaddr = '127.0.0.1',
        port = 1883,
        clean_session = true,
        keepalive = 10,
        id = 'lua-eco-test-' .. id
    })

    local requested_unsub = false

    local function fail(err)
        if lifecycle.done then
            return
        end

        lifecycle.done = true
        lifecycle.err_reason = err or 'unknown error'
        client:close()
        eco.unloop()
    end

    local function success()
        if lifecycle.done then
            return
        end

        lifecycle.done = true
        client:disconnect()
        client:close()
        eco.unloop()
    end

    local function publish_next()
        if not lifecycle.got_publish_q0 then
            local ok, err = client:publish(topic, payload_qos0, mqtt.QOS0, false)
            if not ok then
                fail('publish qos0 failed: ' .. tostring(err))
            end
            return
        end

        if not lifecycle.got_publish_q1 then
            local ok, err = client:publish(topic, payload_qos1, mqtt.QOS1)
            if not ok then
                fail('publish qos1 failed: ' .. tostring(err))
            end
            return
        end

        if not lifecycle.got_publish_q2 then
            local ok, err = client:publish(topic, payload_qos2, mqtt.QOS2)
            if not ok then
                fail('publish qos2 failed: ' .. tostring(err))
            end
            return
        end

        if requested_unsub then
            return
        end

        requested_unsub = true

        local ok, err = client:unsubscribe(topic)
        if not ok then
            fail('unsubscribe failed: ' .. tostring(err))
        end
    end

    client:on('error', function(err, self)
        if lifecycle.done then
            return
        end

        assert(self == client)
        fail('mqtt error: ' .. tostring(err))
    end)

    client:on({
        conack = function(ack, self)
            assert(self == client)

            if ack.rc ~= mqtt.CONNACK_ACCEPTED then
                fail('conack rejected: ' .. tostring(ack.reason or ack.rc))
                return
            end

            lifecycle.got_conack = true

            local ok_bad_qos = pcall(function()
                client:publish(topic, 'bad-qos', 9)
            end)
            assert(not ok_bad_qos, 'publish should reject invalid qos after connected')

            local ok, err = client:subscribe(topic, mqtt.QOS2)
            if not ok then
                fail('subscribe failed: ' .. tostring(err))
            end
        end,

        suback = function(ack, self)
            assert(self == client)

            local results = ack.results
            assert(type(results) == 'table' and #results == 1)

            local r = results[1]

            if r.topic ~= topic then
                return
            end

            if r.rc == mqtt.SUBACK_FAILURE then
                fail('suback failure for topic: ' .. topic)
                return
            end

            lifecycle.got_suback = true
            publish_next()
        end,

        publish = function(msg, self)
            assert(self == client)

            if msg.topic ~= topic then
                return
            end

            if msg.payload == payload_qos0 then
                lifecycle.got_publish_q0 = true
                publish_next()
                return
            end

            if msg.payload == payload_qos1 then
                lifecycle.got_publish_q1 = true
                publish_next()
                return
            end

            if msg.payload == payload_qos2 then
                lifecycle.got_publish_q2 = true
                publish_next()
                return
            end

            if msg.payload == payload_after_unsub then
                fail('received message after unsubscribe')
                return
            end

            fail('received unexpected payload: ' .. tostring(msg.payload))
        end,

        unsuback = function(topic_name, self)
            assert(self == client)
            assert(topic_name == topic)

            lifecycle.got_unsuback = true

            local ok, err = client:publish(topic, payload_after_unsub, mqtt.QOS1)
            if not ok then
                fail('post-unsubscribe publish failed: ' .. tostring(err))
                return
            end

            eco.run(function()
                eco.sleep(0.5)

                if not lifecycle.done then
                    success()
                end
            end)
        end
    })

    eco.run(function()
        client:run()
    end)

    eco.run(function()
        eco.sleep(8)

        if not lifecycle.done then
            fail('timeout waiting mqtt lifecycle flow')
        end
    end)
end)

assert(lifecycle.err_reason == nil, lifecycle.err_reason)
assert(lifecycle.got_conack, 'did not receive CONNACK')
assert(lifecycle.got_suback, 'did not receive SUBACK')
assert(lifecycle.got_publish_q0, 'did not receive QoS0 publish')
assert(lifecycle.got_publish_q1, 'did not receive QoS1 publish')
assert(lifecycle.got_publish_q2, 'did not receive QoS2 publish')
assert(lifecycle.got_unsuback, 'did not receive UNSUBACK')

print('mqtt tests passed')