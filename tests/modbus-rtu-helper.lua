#!/usr/bin/env eco

local modbus = require 'eco.modbus'
local eco = require 'eco'
local time = require 'eco.time'

local device = assert(arg[1], 'expecting serial device')
local action = assert(arg[2], 'expecting test action')
local client = modbus.new_rtu_client({
    device = device,
    timeout = 0.2,
    broadcast_delay = 0.02,
    unit_id = action == 'broadcast' and 0 or 1
})

assert(client:open())

if action == 'read' or action == 'gap' or action == 'flags' or action == 'echo' then
    local values, err = client:read_holding_registers(0, 1)
    print('result', values and values[1], err)
elseif action == 'broadcast' then
    local ok, err = client:write_single_register(0, 7)
    print('result', ok, err)
elseif action == 'gc' then
    client = nil -- luacheck: ignore 311
    collectgarbage('collect')
    collectgarbage('collect')
    print('collected')
    return
elseif action == 'reconnect' then
    local first_done = false
    local queued_done = false
    local first_err
    local queued_err

    eco.run(function()
        local _
        _, first_err = client:read_holding_registers(0, 1)
        first_done = true
    end)

    eco.run(function()
        local _
        _, queued_err = client:read_holding_registers(0, 1)
        queued_done = true
    end)

    time.sleep(0.05)
    client:close()
    assert(client:open())

    while not first_done or not queued_done do
        time.sleep(0.001)
    end

    local values, err = client:read_holding_registers(0, 1)

    print('first', first_err)
    print('queued', queued_err)
    print('new', values and values[1], err)
end

client:close()
