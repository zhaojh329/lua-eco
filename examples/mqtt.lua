#!/usr/bin/env eco

-- https://github.com/flukso/lua-mosquitto

local socket = require 'eco.socket'
local mosq  = require 'mosquitto'
local time = require 'eco.time'
local sys = require 'eco.sys'

local MOSQ_ERR_NO_CONN = 4
local MOSQ_ERR_CONN_LOST = 7

local MOSQ_ID            = 'flukso'
local MOSQ_CLEAN_SESSION = true
local MOSQ_HOST          = '127.0.0.1'
local MOSQ_PORT          = 1883
local MOSQ_KEEPALIVE     = 300
local MOSQ_MAX_READ      = 100 -- packets
local MOSQ_MAX_WRITE     = 100 -- packets

local done = false

local mqtt = mosq.new(MOSQ_ID, MOSQ_CLEAN_SESSION)

mqtt.ON_CONNECT = function(success, rc, str)
    print('connected:', success, rc, str)

    mqtt:subscribe('$SYS/#')
    mqtt:subscribe('eco', 2)
end

mqtt.ON_DISCONNECT = function(success, rc, str)
    print('disconnected', success, rc, str)
    if rc == MOSQ_ERR_CONN_LOST or rc == MOSQ_ERR_NO_CONN then
        done = true
    end
end

mqtt.ON_PUBLISH = function(mid)
    print('on publish: ', mid)
end

mqtt.ON_MESSAGE = function(mid, topic, payload, qos, retain)
    print('on message:', mid, topic, payload, qos, retain)
end

-- mqtt.ON_SUBSCRIBE = function(...) print('SUBSCRIBE', ...) end
-- mqtt.ON_UNSUBSCRIBE = function(...) print('UNSUBSCRIBE', ...) end
-- mqtt.ON_LOG = function(...) print('LOG', ...) end

local function wait_mqtt_connected(fd)
    local w = eco.watcher(eco.IO, fd, eco.WRITE)
    if not w:wait(3.0) then
        return false, 'timeout'
    end

    local err = socket.getoption(fd, 'error')
    if err ~= 0 then
        return false, sys.strerror(err)
    end

    return true
end

local function connect_mqtt()
    local ok, code, err = mqtt:connect_async(MOSQ_HOST, MOSQ_PORT, MOSQ_KEEPALIVE)
    if not ok then
        print('connect fail:', code, err)
        os.exit(1)
    end

    local ok, err = wait_mqtt_connected(mqtt:socket())
    if not ok then
        print('connect fail:', err)
        os.exit(1)
    end
end

connect_mqtt()

eco.run(function()
    local fd = mqtt:socket()
    local w = eco.watcher(eco.IO, fd)
    while not done do
        w:wait()
        local _, err = mqtt:loop_read(MOSQ_MAX_READ)
        if err == MOSQ_ERR_CONN_LOST then
            break
        end
    end
end)

eco.run(function()
    local fd = mqtt:socket()
    local w = eco.watcher(eco.IO, fd, eco.WRITE)
    while not done do
        w:wait()
        if mqtt:want_write() then
            mqtt:loop_write(MOSQ_MAX_WRITE)
        end
    end
end)

eco.run(function()
    while not done do
        time.sleep(3)
        if not done then
            mqtt:loop_misc()
        end
    end
end)
