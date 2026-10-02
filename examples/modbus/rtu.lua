#!/usr/bin/env eco

-- Modbus RTU client example.
--
-- Requires a serial port with a Modbus RTU slave attached, e.g. a USB-RS485
-- adapter at /dev/ttyUSB0.

local modbus = require 'eco.modbus'
local time = require 'eco.time'

local client = modbus.new_rtu_client({
    device = '/dev/ttyUSB0',
    baud = 9600,
    parity = 'E',
    stop_bits = 1,
    unit_id = 1,
    timeout = 1.0
})

local ok, err = client:open()
if not ok then
    print('open fail:', err)
    os.exit(1)
end

-- read 10 holding registers starting at address 0
local values, err, code = client:read_holding_registers(0, 10)
if values then
    print('holding registers:', table.concat(values, ', '))
else
    print('read_holding_registers fail:', err, 'exception code:', code)
end

-- write a single register at address 0 and read it back
ok, err = client:write_single_register(0, 100)
if not ok then
    print('write_single_register fail:', err)
else
    local values, err = client:read_holding_registers(0, 1)
    if values then
        print('register 0 is now:', values[1])
    else
        print('read back fail:', err)
    end
end

-- poll a coil every second
for _ = 1, 5 do
    local coils, err = client:read_coils(0, 1)
    if coils then
        print('coil 0:', coils[1])
    else
        print('read_coils fail:', err)
    end

    time.sleep(1.0)
end

-- restores the original port attributes
client:close()
