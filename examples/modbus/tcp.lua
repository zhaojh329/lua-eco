#!/usr/bin/env eco

-- Modbus TCP client example.
--
-- For testing, you can run a Modbus TCP server locally, e.g. with pymodbus:
--   pip install pymodbus
--   python3 -m pymodbus.server --host 127.0.0.1 --port 5020

local modbus = require 'eco.modbus'
local time = require 'eco.time'

local client = modbus.new_tcp_client({
    ipaddr = '127.0.0.1',
    port = 5020,
    unit_id = 1,
    timeout = 3.0
})

local ok, err = client:connect()
if not ok then
    print('connect fail:', err)
    os.exit(1)
end

-- write single register at address 0
local ok, err = client:write_single_register(0, 0x1234)
if not ok then
    print('write_single_register fail:', err)
end

-- write multiple registers starting at address 1
ok, err = client:write_multiple_registers(1, { 11, 22, 33 })
if not ok then
    print('write_multiple_registers fail:', err)
end

-- write a coil
ok, err = client:write_single_coil(0, true)
if not ok then
    print('write_single_coil fail:', err)
end

while true do
    local values, err, code = client:read_holding_registers(0, 4)
    if not values then
        print('read_holding_registers fail:', err, 'exception code:', code)
        break
    end

    print('holding registers:', table.concat(values, ', '))

    local coils, err = client:read_coils(0, 4)
    if coils then
        local bits = {}
        for i, v in ipairs(coils) do
            bits[i] = v and 1 or 0
        end
        print('coils:', table.concat(bits, ', '))
    else
        print('read_coils fail:', err)
    end

    time.sleep(1.0)
end

client:close()
