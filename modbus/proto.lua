-- SPDX-License-Identifier: MIT
-- Author: ziye.chen <ziye.chen@gl-inet.com>

--- Modbus protocol data unit (PDU) codec and shared constants.
--
-- This module implements the transport-independent parts of the Modbus
-- Application Protocol (V1.1b3): function codes, exception codes, request
-- packing, response unpacking and the CRC16 used by Modbus RTU.
--
-- It is used internally by @{eco.modbus.tcp} and @{eco.modbus.rtu}. You
-- normally do not need to use this module directly; see @{eco.modbus}.
--
-- @module eco.modbus.proto

local str_byte = string.byte
local str_char = string.char
local str_pack = string.pack
local str_unpack = string.unpack
local str_fmt = string.format

local M = {
    --- Function code: read coils.
    FC_READ_COILS = 0x01,
    --- Function code: read discrete inputs.
    FC_READ_DISCRETE_INPUTS = 0x02,
    --- Function code: read holding registers.
    FC_READ_HOLDING_REGISTERS = 0x03,
    --- Function code: read input registers.
    FC_READ_INPUT_REGISTERS = 0x04,
    --- Function code: write single coil.
    FC_WRITE_SINGLE_COIL = 0x05,
    --- Function code: write single register.
    FC_WRITE_SINGLE_REGISTER = 0x06,
    --- Function code: write multiple coils.
    FC_WRITE_MULTIPLE_COILS = 0x0F,
    --- Function code: write multiple registers.
    FC_WRITE_MULTIPLE_REGISTERS = 0x10,

    --- Exception code: illegal function.
    EXCEPTION_ILLEGAL_FUNCTION = 0x01,
    --- Exception code: illegal data address.
    EXCEPTION_ILLEGAL_DATA_ADDRESS = 0x02,
    --- Exception code: illegal data value.
    EXCEPTION_ILLEGAL_DATA_VALUE = 0x03,
    --- Exception code: slave device failure.
    EXCEPTION_SLAVE_DEVICE_FAILURE = 0x04,
    --- Exception code: acknowledge.
    EXCEPTION_ACKNOWLEDGE = 0x05,
    --- Exception code: slave device busy.
    EXCEPTION_SLAVE_DEVICE_BUSY = 0x06,
    --- Exception code: memory parity error.
    EXCEPTION_MEMORY_PARITY_ERROR = 0x08,
    --- Exception code: gateway path unavailable.
    EXCEPTION_GATEWAY_PATH_UNAVAILABLE = 0x0A,
    --- Exception code: gateway target device failed to respond.
    EXCEPTION_GATEWAY_TARGET_FAILED_TO_RESPOND = 0x0B,

    --- Maximum quantity for reading coils/discrete inputs in one request.
    MAX_READ_BITS = 2000,
    --- Maximum quantity for reading registers in one request.
    MAX_READ_REGISTERS = 125,
    --- Maximum quantity for writing multiple coils in one request.
    MAX_WRITE_BITS = 1968,
    --- Maximum quantity for writing multiple registers in one request.
    MAX_WRITE_REGISTERS = 123
}

local exception_descriptions = {
    [M.EXCEPTION_ILLEGAL_FUNCTION] = 'illegal function',
    [M.EXCEPTION_ILLEGAL_DATA_ADDRESS] = 'illegal data address',
    [M.EXCEPTION_ILLEGAL_DATA_VALUE] = 'illegal data value',
    [M.EXCEPTION_SLAVE_DEVICE_FAILURE] = 'slave device failure',
    [M.EXCEPTION_ACKNOWLEDGE] = 'acknowledge',
    [M.EXCEPTION_SLAVE_DEVICE_BUSY] = 'slave device busy',
    [M.EXCEPTION_MEMORY_PARITY_ERROR] = 'memory parity error',
    [M.EXCEPTION_GATEWAY_PATH_UNAVAILABLE] = 'gateway path unavailable',
    [M.EXCEPTION_GATEWAY_TARGET_FAILED_TO_RESPOND] = 'gateway target device failed to respond'
}

--- Get the description of a Modbus exception code.
-- @tparam integer code Exception code.
-- @treturn string Description ('unknown exception' if not defined).
function M.exception_description(code)
    return exception_descriptions[code] or 'unknown exception'
end

--- Validate a Modbus data address (raises an error on invalid input).
-- @tparam integer address Data address (0 - 65535).
function M.check_address(address)
    assert(math.type(address) == 'integer' and address >= 0 and address <= 0xFFFF,
           'expecting address to be an integer between 0 and 65535')
end

--- Validate a Modbus serial-line unit identifier (raises on invalid input).
--
-- Address 0 is the serial broadcast address. Callers must enforce that it is
-- only used for write requests and that no response is expected.
--
-- @tparam integer unit_id Unit identifier (0 - 247).
function M.check_rtu_unit_id(unit_id)
    assert(math.type(unit_id) == 'integer' and unit_id >= 0 and unit_id <= 247,
           'expecting unit_id to be an integer between 0 and 247')
end

--- Validate a Modbus TCP unit identifier (raises on invalid input).
-- @tparam integer unit_id Unit identifier (0 - 255).
function M.check_tcp_unit_id(unit_id)
    assert(math.type(unit_id) == 'integer' and unit_id >= 0 and unit_id <= 0xFF,
           'expecting unit_id to be an integer between 0 and 255')
end

-- Backward-compatible alias for the original serial-address validator.
M.check_unit_id = M.check_rtu_unit_id

local function check_quantity(quantity, max)
    assert(math.type(quantity) == 'integer' and quantity >= 1 and quantity <= max,
           str_fmt('expecting quantity to be an integer between 1 and %d', max))
end

local function check_values(values, max)
    assert(type(values) == 'table', 'expecting values to be a table')

    local count = 0
    local max_index = 0

    for index in next, values do
        assert(math.type(index) == 'integer' and index >= 1,
               'expecting values to be an array with positive integer indexes')

        count = count + 1
        if index > max_index then
            max_index = index
        end
    end

    assert(count == max_index, 'expecting values to be a sequence without holes')
    check_quantity(count, max)

    return count
end

--- Compute the Modbus RTU CRC16 (poly 0xA001, init 0xFFFF).
-- @tparam string data Data bytes.
-- @treturn integer CRC value (0 - 65535).
function M.crc16(data)
    local crc = 0xFFFF

    for i = 1, #data do
        crc = crc ~ str_byte(data, i)

        for _ = 1, 8 do
            if crc & 1 ~= 0 then
                crc = (crc >> 1) ~ 0xA001
            else
                crc = crc >> 1
            end
        end
    end

    return crc
end

--- Pack a read coils/discrete inputs request PDU.
-- @tparam integer fc One of @{FC_READ_COILS}, @{FC_READ_DISCRETE_INPUTS}.
-- @tparam integer address Starting address.
-- @tparam integer quantity Quantity of bits (1 - @{MAX_READ_BITS}).
-- @treturn string Request PDU.
function M.pack_read_bits_request(fc, address, quantity)
    M.check_address(address)
    check_quantity(quantity, M.MAX_READ_BITS)

    return str_pack('>I1I2I2', fc, address, quantity)
end

--- Pack a read holding/input registers request PDU.
-- @tparam integer fc One of @{FC_READ_HOLDING_REGISTERS}, @{FC_READ_INPUT_REGISTERS}.
-- @tparam integer address Starting address.
-- @tparam integer quantity Quantity of registers (1 - @{MAX_READ_REGISTERS}).
-- @treturn string Request PDU.
function M.pack_read_registers_request(fc, address, quantity)
    M.check_address(address)
    check_quantity(quantity, M.MAX_READ_REGISTERS)

    return str_pack('>I1I2I2', fc, address, quantity)
end

--- Pack a write single coil request PDU.
-- @tparam integer address Coil address.
-- @tparam boolean value Coil value.
-- @treturn string Request PDU.
function M.pack_write_single_coil_request(address, value)
    M.check_address(address)
    assert(type(value) == 'boolean', 'expecting value to be a boolean')

    return str_pack('>I1I2I2', M.FC_WRITE_SINGLE_COIL, address, value and 0xFF00 or 0x0000)
end

--- Pack a write single register request PDU.
-- @tparam integer address Register address.
-- @tparam integer value Register value (0 - 65535).
-- @treturn string Request PDU.
function M.pack_write_single_register_request(address, value)
    M.check_address(address)
    assert(math.type(value) == 'integer' and value >= 0 and value <= 0xFFFF,
           'expecting value to be an integer between 0 and 65535')

    return str_pack('>I1I2I2', M.FC_WRITE_SINGLE_REGISTER, address, value)
end

--- Pack a write multiple coils request PDU.
-- @tparam integer address Starting address.
-- @tparam table values Array of booleans (1 - @{MAX_WRITE_BITS} items).
-- @treturn string Request PDU.
function M.pack_write_multiple_coils_request(address, values)
    M.check_address(address)
    local quantity = check_values(values, M.MAX_WRITE_BITS)

    local byte_count = (quantity + 7) // 8
    local buf = { str_pack('>I1I2I2I1', M.FC_WRITE_MULTIPLE_COILS, address, quantity, byte_count) }

    for i = 1, byte_count do
        local byte = 0

        for b = 0, 7 do
            local idx = (i - 1) * 8 + b + 1
            local v = rawget(values, idx)

            if idx <= quantity then
                assert(type(v) == 'boolean',
                       str_fmt('expecting values[%d] to be a boolean', idx))

                if v then
                    byte = byte | 1 << b
                end
            end
        end

        buf[#buf + 1] = str_char(byte)
    end

    return table.concat(buf)
end

--- Pack a write multiple registers request PDU.
-- @tparam integer address Starting address.
-- @tparam table values Array of integers (1 - @{MAX_WRITE_REGISTERS} items, each 0 - 65535).
-- @treturn string Request PDU.
function M.pack_write_multiple_registers_request(address, values)
    M.check_address(address)
    local quantity = check_values(values, M.MAX_WRITE_REGISTERS)

    local buf = { str_pack('>I1I2I2I1', M.FC_WRITE_MULTIPLE_REGISTERS,
                           address, quantity, quantity * 2) }

    for i = 1, quantity do
        local v = rawget(values, i)

        assert(math.type(v) == 'integer' and v >= 0 and v <= 0xFFFF,
               str_fmt('expecting values[%d] to be an integer between 0 and 65535', i))

        buf[#buf + 1] = str_pack('>I2', v)
    end

    return table.concat(buf)
end

--- Check a response PDU for exceptions.
--
-- Returns `true` for a normal response, `(nil, err, code)` for a Modbus
-- exception response, and `(nil, err)` for a malformed/unexpected response.
--
-- @tparam integer fc Expected function code.
-- @tparam string pdu Response PDU.
-- @treturn[1] boolean true On normal response.
-- @treturn[2] nil On exception or malformed response.
-- @treturn[2] string Error message.
-- @treturn[2] integer Exception code (only for Modbus exception responses).
function M.check_exception(fc, pdu)
    if #pdu < 2 then
        return nil, 'malformed response: PDU too short'
    end

    local rfc = str_byte(pdu, 1)

    if rfc == fc then
        return true
    end

    if rfc == fc | 0x80 then
        if #pdu ~= 2 then
            return nil, str_fmt('malformed exception response: expecting 2 bytes, got %d', #pdu)
        end

        local code = str_byte(pdu, 2)
        return nil, 'modbus exception: ' .. M.exception_description(code), code
    end

    return nil, str_fmt('unexpected function code in response: 0x%02x (expecting 0x%02x)', rfc, fc)
end

--- Unpack a read coils/discrete inputs response PDU.
--
-- Must only be called after @{check_exception} succeeded.
--
-- @tparam string pdu Response PDU.
-- @tparam integer quantity Quantity of bits requested.
-- @treturn[1] table Array of booleans (length = `quantity`).
-- @treturn[2] nil On malformed response.
-- @treturn[2] string Error message.
function M.unpack_read_bits_response(pdu, quantity)
    if #pdu < 2 then
        return nil, 'malformed response: missing byte count'
    end

    local byte_count = str_byte(pdu, 2)

    if byte_count ~= (quantity + 7) // 8 or #pdu ~= 2 + byte_count then
        return nil, str_fmt('malformed response: byte count %d does not match quantity %d',
                            byte_count, quantity)
    end

    local used_bits = quantity % 8
    if used_bits ~= 0 then
        local unused_mask = (~((1 << used_bits) - 1)) & 0xFF

        if str_byte(pdu, #pdu) & unused_mask ~= 0 then
            return nil, 'malformed response: unused bits in final data byte are not zero'
        end
    end

    local values = {}

    for i = 1, quantity do
        local byte = str_byte(pdu, 3 + (i - 1) // 8)
        values[i] = byte & (1 << (i - 1) % 8) ~= 0
    end

    return values
end

--- Unpack a read holding/input registers response PDU.
--
-- Must only be called after @{check_exception} succeeded.
--
-- @tparam string pdu Response PDU.
-- @tparam integer quantity Quantity of registers requested.
-- @treturn[1] table Array of unsigned 16-bit integers (length = `quantity`).
-- @treturn[2] nil On malformed response.
-- @treturn[2] string Error message.
function M.unpack_read_registers_response(pdu, quantity)
    if #pdu < 2 then
        return nil, 'malformed response: missing byte count'
    end

    local byte_count = str_byte(pdu, 2)

    if byte_count ~= quantity * 2 or #pdu ~= 2 + byte_count then
        return nil, str_fmt('malformed response: byte count %d does not match quantity %d',
                            byte_count, quantity)
    end

    local values = {}

    for i = 1, quantity do
        values[i] = str_unpack('>I2', pdu, 3 + (i - 1) * 2)
    end

    return values
end

--- Unpack and verify a write echo response PDU (FC 0x05/0x06/0x0F/0x10).
--
-- Must only be called after @{check_exception} succeeded.
--
-- @tparam string pdu Response PDU.
-- @tparam integer address Address sent in the request.
-- @tparam integer value Value/quantity sent in the request.
-- @treturn[1] boolean true On matching echo.
-- @treturn[2] nil On malformed or mismatching response.
-- @treturn[2] string Error message.
function M.unpack_write_echo_response(pdu, address, value)
    if #pdu ~= 5 then
        return nil, str_fmt('malformed response: expecting 5 bytes, got %d', #pdu)
    end

    local raddr, rvalue = str_unpack('>I2I2', pdu, 2)

    if raddr ~= address or rvalue ~= value then
        return nil, str_fmt('response echo mismatch: expecting (%d, %d), got (%d, %d)',
                            address, value, raddr, rvalue)
    end

    return true
end

--- Compute the expected data length of a normal response PDU (without the
-- function code byte) for a given request.
--
-- Used by the Modbus RTU transport to frame responses without relying on
-- timing gaps.
--
-- @tparam integer fc Request function code.
-- @tparam[opt] integer quantity Quantity requested (only for read requests).
-- @treturn integer Expected response PDU length minus one (function code byte excluded),
-- or nil if the function code is unknown.
function M.response_data_length(fc, quantity)
    if fc == M.FC_READ_COILS or fc == M.FC_READ_DISCRETE_INPUTS then
        return 1 + (quantity + 7) // 8
    end

    if fc == M.FC_READ_HOLDING_REGISTERS or fc == M.FC_READ_INPUT_REGISTERS then
        return 1 + quantity * 2
    end

    if fc == M.FC_WRITE_SINGLE_COIL or fc == M.FC_WRITE_SINGLE_REGISTER or
       fc == M.FC_WRITE_MULTIPLE_COILS or fc == M.FC_WRITE_MULTIPLE_REGISTERS then
        return 4
    end

    return nil
end

return M
