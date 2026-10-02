-- SPDX-License-Identifier: MIT
-- Author: ziye.chen <ziye.chen@gl-inet.com>

--- Modbus client (master) for TCP and RTU transports.
--
-- This is the entry point of the Modbus support. It re-exports the shared
-- constants from @{eco.modbus.proto} and provides factory functions for
-- the two transports:
--
-- - @{new_tcp_client}: Modbus TCP over Ethernet (see @{eco.modbus.tcp})
-- - @{new_rtu_client}: Modbus RTU over a serial port (see @{eco.modbus.rtu})
--
-- Supported function codes:
--
-- - `0x01` read coils
-- - `0x02` read discrete inputs
-- - `0x03` read holding registers
-- - `0x04` read input registers
-- - `0x05` write single coil
-- - `0x06` write single register
-- - `0x0F` write multiple coils
-- - `0x10` write multiple registers
--
-- @module eco.modbus
-- @usage
-- #!/usr/bin/env eco
--
-- local modbus = require 'eco.modbus'
--
-- local client = modbus.new_tcp_client({ ipaddr = '192.168.1.10', unit_id = 0xFF })
-- assert(client:connect())
--
-- local values, err = client:read_holding_registers(0, 10)
-- assert(values, err)
--
-- client:close()

local proto = require 'eco.modbus.proto'

local M = {
    --- Function code: read coils.
    READ_COILS = proto.FC_READ_COILS,
    --- Function code: read discrete inputs.
    READ_DISCRETE_INPUTS = proto.FC_READ_DISCRETE_INPUTS,
    --- Function code: read holding registers.
    READ_HOLDING_REGISTERS = proto.FC_READ_HOLDING_REGISTERS,
    --- Function code: read input registers.
    READ_INPUT_REGISTERS = proto.FC_READ_INPUT_REGISTERS,
    --- Function code: write single coil.
    WRITE_SINGLE_COIL = proto.FC_WRITE_SINGLE_COIL,
    --- Function code: write single register.
    WRITE_SINGLE_REGISTER = proto.FC_WRITE_SINGLE_REGISTER,
    --- Function code: write multiple coils.
    WRITE_MULTIPLE_COILS = proto.FC_WRITE_MULTIPLE_COILS,
    --- Function code: write multiple registers.
    WRITE_MULTIPLE_REGISTERS = proto.FC_WRITE_MULTIPLE_REGISTERS,

    --- Exception code: illegal function.
    EXCEPTION_ILLEGAL_FUNCTION = proto.EXCEPTION_ILLEGAL_FUNCTION,
    --- Exception code: illegal data address.
    EXCEPTION_ILLEGAL_DATA_ADDRESS = proto.EXCEPTION_ILLEGAL_DATA_ADDRESS,
    --- Exception code: illegal data value.
    EXCEPTION_ILLEGAL_DATA_VALUE = proto.EXCEPTION_ILLEGAL_DATA_VALUE,
    --- Exception code: slave device failure.
    EXCEPTION_SLAVE_DEVICE_FAILURE = proto.EXCEPTION_SLAVE_DEVICE_FAILURE,
    --- Exception code: acknowledge.
    EXCEPTION_ACKNOWLEDGE = proto.EXCEPTION_ACKNOWLEDGE,
    --- Exception code: slave device busy.
    EXCEPTION_SLAVE_DEVICE_BUSY = proto.EXCEPTION_SLAVE_DEVICE_BUSY,
    --- Exception code: memory parity error.
    EXCEPTION_MEMORY_PARITY_ERROR = proto.EXCEPTION_MEMORY_PARITY_ERROR,
    --- Exception code: gateway path unavailable.
    EXCEPTION_GATEWAY_PATH_UNAVAILABLE = proto.EXCEPTION_GATEWAY_PATH_UNAVAILABLE,
    --- Exception code: gateway target device failed to respond.
    EXCEPTION_GATEWAY_TARGET_FAILED_TO_RESPOND = proto.EXCEPTION_GATEWAY_TARGET_FAILED_TO_RESPOND
}

--- Create a new Modbus TCP client.
--
-- See @{eco.modbus.tcp.new} for the available options.
--
-- @tparam table opts Options table (e.g. `{ ipaddr = '192.168.1.10' }`).
-- @treturn client Modbus TCP client.
function M.new_tcp_client(opts)
    return require('eco.modbus.tcp').new(opts)
end

--- Create a new Modbus RTU client.
--
-- See @{eco.modbus.rtu.new} for the available options.
--
-- @tparam table opts Options table (e.g. `{ device = '/dev/ttyUSB0' }`).
-- @treturn client Modbus RTU client.
function M.new_rtu_client(opts)
    return require('eco.modbus.rtu').new(opts)
end

return M
