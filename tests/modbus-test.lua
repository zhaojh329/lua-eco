#!/usr/bin/env eco

local socket = require 'eco.socket'
local modbus = require 'eco.modbus'
local proto = require 'eco.modbus.proto'
local eco = require 'eco'
local time = require 'eco.time'
local test = require 'test'

local str_byte = string.byte
local str_char = string.char
local str_pack = string.pack
local str_unpack = string.unpack
local str_fmt = string.format

test.run_case_sync('modbus constants', function()
    assert(modbus.READ_COILS == 0x01)
    assert(modbus.READ_DISCRETE_INPUTS == 0x02)
    assert(modbus.READ_HOLDING_REGISTERS == 0x03)
    assert(modbus.READ_INPUT_REGISTERS == 0x04)
    assert(modbus.WRITE_SINGLE_COIL == 0x05)
    assert(modbus.WRITE_SINGLE_REGISTER == 0x06)
    assert(modbus.WRITE_MULTIPLE_COILS == 0x0F)
    assert(modbus.WRITE_MULTIPLE_REGISTERS == 0x10)

    assert(modbus.EXCEPTION_ILLEGAL_FUNCTION == 0x01)
    assert(modbus.EXCEPTION_ILLEGAL_DATA_ADDRESS == 0x02)
    assert(modbus.EXCEPTION_ILLEGAL_DATA_VALUE == 0x03)
    assert(modbus.EXCEPTION_SLAVE_DEVICE_FAILURE == 0x04)
    assert(modbus.EXCEPTION_ACKNOWLEDGE == 0x05)
    assert(modbus.EXCEPTION_SLAVE_DEVICE_BUSY == 0x06)
    assert(modbus.EXCEPTION_MEMORY_PARITY_ERROR == 0x08)
    assert(modbus.EXCEPTION_GATEWAY_PATH_UNAVAILABLE == 0x0A)
    assert(modbus.EXCEPTION_GATEWAY_TARGET_FAILED_TO_RESPOND == 0x0B)

    assert(proto.MAX_READ_BITS == 2000)
    assert(proto.MAX_READ_REGISTERS == 125)
    assert(proto.MAX_WRITE_BITS == 1968)
    assert(proto.MAX_WRITE_REGISTERS == 123)
end)

test.run_case_sync('modbus crc16', function()
    -- well-known check vector
    assert(proto.crc16('123456789') == 0x4B37)

    -- Modbus RTU frame example: 01 03 00 00 00 0A -> CRC 0xCDC5
    assert(proto.crc16('\x01\x03\x00\x00\x00\x0A') == 0xCDC5)

    -- empty input keeps the initial value
    assert(proto.crc16('') == 0xFFFF)
end)

test.run_case_sync('modbus pack requests', function()
    local pdu = proto.pack_read_bits_request(proto.FC_READ_COILS, 0x0013, 0x0025)
    assert(pdu == '\x01\x00\x13\x00\x25')

    pdu = proto.pack_read_registers_request(proto.FC_READ_HOLDING_REGISTERS, 0x006B, 3)
    assert(pdu == '\x03\x00\x6B\x00\x03')

    pdu = proto.pack_write_single_coil_request(0x00AC, true)
    assert(pdu == '\x05\x00\xAC\xFF\x00')

    pdu = proto.pack_write_single_coil_request(0x00AC, false)
    assert(pdu == '\x05\x00\xAC\x00\x00')

    pdu = proto.pack_write_single_register_request(0x0001, 0x0003)
    assert(pdu == '\x06\x00\x01\x00\x03')

    -- 10 coils: CD 6B B2 -> bytes 0xCD 0x6B (bits 0-7, 8-9)
    pdu = proto.pack_write_multiple_coils_request(0x0013,
        { true, false, true, true, false, false, true, true, true, false })
    assert(pdu == '\x0F\x00\x13\x00\x0A\x02\xCD\x01')

    pdu = proto.pack_write_multiple_registers_request(0x0001, { 0x000A, 0x0102 })
    assert(pdu == '\x10\x00\x01\x00\x02\x04\x00\x0A\x01\x02')
end)

test.run_case_sync('modbus pack request validations', function()
    test.expect_error_contains(function()
        proto.pack_read_bits_request(proto.FC_READ_COILS, -1, 1)
    end, 'expecting address to be an integer between 0 and 65535')

    test.expect_error_contains(function()
        proto.pack_read_bits_request(proto.FC_READ_COILS, 0x10000, 1)
    end, 'expecting address to be an integer between 0 and 65535')

    test.expect_error_contains(function()
        proto.pack_read_bits_request(proto.FC_READ_COILS, 0, 0)
    end, 'expecting quantity to be an integer between 1 and 2000')

    test.expect_error_contains(function()
        proto.pack_read_bits_request(proto.FC_READ_COILS, 0, 2001)
    end, 'expecting quantity to be an integer between 1 and 2000')

    test.expect_error_contains(function()
        proto.pack_read_registers_request(proto.FC_READ_HOLDING_REGISTERS, 0, 126)
    end, 'expecting quantity to be an integer between 1 and 125')

    test.expect_error_contains(function()
        proto.pack_write_single_coil_request(0, 1)
    end, 'expecting value to be a boolean')

    test.expect_error_contains(function()
        proto.pack_write_single_register_request(0, 0x10000)
    end, 'expecting value to be an integer between 0 and 65535')

    test.expect_error_contains(function()
        proto.pack_write_multiple_coils_request(0, {})
    end, 'expecting quantity to be an integer between 1 and 1968')

    test.expect_error_contains(function()
        proto.pack_write_multiple_coils_request(0, { true, 1 })
    end, 'expecting values[2] to be a boolean')

    test.expect_error_contains(function()
        proto.pack_write_multiple_registers_request(0, { 0, -1 })
    end, 'expecting values[2] to be an integer between 0 and 65535')

    test.expect_error_contains(function()
        proto.pack_write_multiple_registers_request(0, {})
    end, 'expecting quantity to be an integer between 1 and 123')

    test.expect_error_contains(function()
        proto.pack_write_multiple_coils_request(0, { true, nil, true })
    end, 'expecting values to be a sequence without holes')

    test.expect_error_contains(function()
        proto.pack_write_multiple_registers_request(0, { [1] = 1, [3] = 3 })
    end, 'expecting values to be a sequence without holes')

    test.expect_error_contains(function()
        proto.pack_write_multiple_registers_request(0, { [0] = 1, [1] = 2 })
    end, 'expecting values to be an array with positive integer indexes')
end)

test.run_case_sync('modbus check exception', function()
    local ok, err, code = proto.check_exception(0x03, '\x03\x04\x00\x01\x00\x02')
    assert(ok == true and err == nil and code == nil)

    ok, err, code = proto.check_exception(0x03, '\x83\x02')
    assert(ok == nil and code == 0x02)
    assert(err == 'modbus exception: illegal data address')

    ok, err = proto.check_exception(0x03, '\x83\x63')
    assert(ok == nil and err == 'modbus exception: unknown exception')

    ok, err = proto.check_exception(0x03, '\x04\x00')
    assert(ok == nil)
    assert(err:find('unexpected function code', 1, true))

    ok, err = proto.check_exception(0x03, '\x03')
    assert(ok == nil)
    assert(err:find('PDU too short', 1, true))

    ok, err = proto.check_exception(0x03, '\x83\x02\x99')
    assert(ok == nil)
    assert(err:find('malformed exception response', 1, true))
end)

test.run_case_sync('modbus unpack responses', function()
    -- read coils: 3 bits set (1, 0, 1)
    local values, err = proto.unpack_read_bits_response('\x01\x01\x05', 3)
    assert(values and err == nil)
    assert(#values == 3)
    assert(values[1] == true and values[2] == false and values[3] == true)

    -- byte count padding: 10 bits in 2 bytes
    values = proto.unpack_read_bits_response('\x01\x02\xCD\x01', 10)
    assert(#values == 10)
    assert(values[1] == true and values[2] == false and values[3] == true)
    assert(values[9] == true and values[10] == false)

    values, err = proto.unpack_read_bits_response('\x01\x02\x05', 3)
    assert(values == nil)
    assert(err:find('byte count', 1, true))

    values, err = proto.unpack_read_bits_response('\x01\x01\xFD', 3)
    assert(values == nil)
    assert(err:find('unused bits', 1, true))

    values, err = proto.unpack_read_registers_response('\x03\x04\x00\x06\x00\x05', 2)
    assert(values and err == nil)
    assert(#values == 2 and values[1] == 6 and values[2] == 5)

    values, err = proto.unpack_read_registers_response('\x03\x04\x00\x06', 2)
    assert(values == nil)
    assert(err:find('byte count', 1, true))

    local ok
    ok, err = proto.unpack_write_echo_response('\x06\x00\x01\x00\x03', 1, 3)
    assert(ok == true and err == nil)

    ok, err = proto.unpack_write_echo_response('\x06\x00\x01\x00\x04', 1, 3)
    assert(ok == nil)
    assert(err:find('echo mismatch', 1, true))

    ok, err = proto.unpack_write_echo_response('\x06\x00\x01', 1, 3)
    assert(ok == nil)
    assert(err:find('expecting 5 bytes', 1, true))
end)

test.run_case_sync('modbus response data length', function()
    assert(proto.response_data_length(proto.FC_READ_COILS, 1) == 2)
    assert(proto.response_data_length(proto.FC_READ_COILS, 9) == 3)
    assert(proto.response_data_length(proto.FC_READ_DISCRETE_INPUTS, 2000) == 251)
    assert(proto.response_data_length(proto.FC_READ_HOLDING_REGISTERS, 1) == 3)
    assert(proto.response_data_length(proto.FC_READ_INPUT_REGISTERS, 125) == 251)
    assert(proto.response_data_length(proto.FC_WRITE_SINGLE_COIL) == 4)
    assert(proto.response_data_length(proto.FC_WRITE_SINGLE_REGISTER) == 4)
    assert(proto.response_data_length(proto.FC_WRITE_MULTIPLE_COILS) == 4)
    assert(proto.response_data_length(proto.FC_WRITE_MULTIPLE_REGISTERS) == 4)
    assert(proto.response_data_length(0x2B) == nil)
end)

test.run_case_sync('modbus client validations', function()
    test.expect_error_contains(function()
        modbus.new_tcp_client(1)
    end, 'expecting opts to be a table')

    test.expect_error_contains(function()
        modbus.new_tcp_client({})
    end, 'expecting ipaddr')

    test.expect_error_contains(function()
        modbus.new_tcp_client({ ipaddr = 1 })
    end, 'expecting ipaddr to be a string')

    test.expect_error_contains(function()
        modbus.new_tcp_client({ ipaddr = 'not-an-ip' })
    end, 'expecting ipaddr to be a valid IPv4 or IPv6 address')

    test.expect_error_contains(function()
        modbus.new_tcp_client({ ipaddr = '127.0.0.1', port = 1.5 })
    end, 'expecting port to be an integer between 1 and 65535')

    test.expect_error_contains(function()
        modbus.new_tcp_client({ ipaddr = '127.0.0.1', port = 0 })
    end, 'expecting port to be an integer between 1 and 65535')

    test.expect_error_contains(function()
        modbus.new_tcp_client({ ipaddr = '127.0.0.1', unit_id = 256 })
    end, 'expecting unit_id to be an integer between 0 and 255')

    test.expect_error_contains(function()
        modbus.new_tcp_client({ ipaddr = '127.0.0.1', timeout = 'x' })
    end, 'expecting timeout to be a finite positive number')

    test.expect_error_contains(function()
        modbus.new_tcp_client({ ipaddr = '127.0.0.1', timeout = 0 })
    end, 'expecting timeout to be a finite positive number')

    test.expect_error_contains(function()
        modbus.new_tcp_client({ ipaddr = '127.0.0.1', timeout = 0 / 0 })
    end, 'expecting timeout to be a finite positive number')

    local c = modbus.new_tcp_client({ ipaddr = '127.0.0.1' })
    assert(c:connected() == false)
    assert(c.unit_id == 0xFF)

    local values, err = c:read_coils(0, 1)
    assert(values == nil and err == 'unconnected')

    c:set_unit_id(255)
    c:close()

    test.expect_error_contains(function()
        modbus.new_rtu_client({})
    end, 'expecting device')

    test.expect_error_contains(function()
        modbus.new_rtu_client({ device = '/dev/ttyUSB0', baud = 1000 })
    end, 'expecting a supported baud rate')

    test.expect_error_contains(function()
        modbus.new_rtu_client({ device = '/dev/ttyUSB0', parity = 'X' })
    end, "expecting parity to be one of 'N', 'E', 'O'")

    test.expect_error_contains(function()
        modbus.new_rtu_client({ device = '/dev/ttyUSB0', stop_bits = 3 })
    end, 'expecting stop_bits to be 1 or 2')

    test.expect_error_contains(function()
        modbus.new_rtu_client({ device = '/dev/ttyUSB0', parity = 'N', stop_bits = 1 })
    end, 'expecting one stop bit with parity or two stop bits without parity')

    test.expect_error_contains(function()
        modbus.new_rtu_client({ device = '/dev/ttyUSB0', timeout = -1 })
    end, 'expecting timeout to be a finite positive number')

    local rc = modbus.new_rtu_client({ device = '/dev/ttyUSB0' })
    assert(rc:opened() == false)
    assert(rc.opts.parity == 'E' and rc.opts.stop_bits == 1)

    local no_parity = modbus.new_rtu_client({
        device = '/dev/ttyUSB0',
        parity = 'N'
    })
    assert(no_parity.opts.stop_bits == 2)

    values, err = rc:read_coils(0, 1)
    assert(values == nil and err == 'not opened')

    rc:close()
end)

-- a minimal Modbus TCP server (slave) used for loopback tests
local function handle_slave_request(state, pdu)
    local fc = str_byte(pdu, 1)

    if fc == modbus.READ_COILS or fc == modbus.READ_DISCRETE_INPUTS then
        local addr, quantity = str_unpack('>I2I2', pdu, 2)

        if addr >= 0x8000 then
            return str_char(fc | 0x80, modbus.EXCEPTION_ILLEGAL_DATA_ADDRESS)
        end

        local t = fc == modbus.READ_COILS and state.coils or state.discrete_inputs
        local byte_count = (quantity + 7) // 8
        local bytes = {}

        for i = 0, quantity - 1 do
            if t[addr + i] then
                local idx = i // 8 + 1
                bytes[idx] = (bytes[idx] or 0) | 1 << i % 8
            end
        end

        local resp = { str_char(fc, byte_count) }

        for i = 1, byte_count do
            resp[#resp + 1] = str_char(bytes[i] or 0)
        end

        return table.concat(resp)
    end

    if fc == modbus.READ_HOLDING_REGISTERS or fc == modbus.READ_INPUT_REGISTERS then
        local addr, quantity = str_unpack('>I2I2', pdu, 2)

        if addr >= 0x8000 then
            return str_char(fc | 0x80, modbus.EXCEPTION_ILLEGAL_DATA_ADDRESS)
        end

        local t = fc == modbus.READ_HOLDING_REGISTERS and state.holding_registers
            or state.input_registers
        local resp = { str_char(fc, quantity * 2) }

        for i = 0, quantity - 1 do
            resp[#resp + 1] = str_pack('>I2', t[addr + i] or 0)
        end

        return table.concat(resp)
    end

    if fc == modbus.WRITE_SINGLE_COIL then
        local addr, value = str_unpack('>I2I2', pdu, 2)
        state.coils[addr] = value == 0xFF00
        return pdu
    end

    if fc == modbus.WRITE_SINGLE_REGISTER then
        local addr, value = str_unpack('>I2I2', pdu, 2)
        state.holding_registers[addr] = value
        return pdu
    end

    if fc == modbus.WRITE_MULTIPLE_COILS then
        local addr, quantity = str_unpack('>I2I2', pdu, 2)

        for i = 0, quantity - 1 do
            local byte = str_byte(pdu, 7 + i // 8)
            state.coils[addr + i] = byte & (1 << i % 8) ~= 0
        end

        return pdu:sub(1, 5)
    end

    if fc == modbus.WRITE_MULTIPLE_REGISTERS then
        local addr, quantity = str_unpack('>I2I2', pdu, 2)

        for i = 0, quantity - 1 do
            state.holding_registers[addr + i] = str_unpack('>I2', pdu, 7 + i * 2)
        end

        return pdu:sub(1, 5)
    end

    return str_char(fc | 0x80, modbus.EXCEPTION_ILLEGAL_FUNCTION)
end

local function start_mock_server(state)
    local srv, err = socket.listen_tcp('127.0.0.1', 0)
    assert(srv, err)

    local port = srv:getsockname().port

    eco.run(function()
        while true do
            local con = srv:accept()
            if not con then
                return
            end

            eco.run(function()
                while true do
                    local hdr = con:readfull(7)
                    if not hdr then
                        break
                    end

                    local tid, pid, len, uid = str_unpack('>I2I2I2I1', hdr)
                    local pdu = con:readfull(len - 1)
                    if not pdu then
                        break
                    end

                    local resp = handle_slave_request(state, pdu)

                    if not con:send(str_pack('>I2I2I2', tid, pid, #resp + 1) .. str_char(uid) .. resp) then
                        break
                    end
                end

                con:close()
            end)
        end
    end)

    return srv, port
end

local function read_tcp_request(con)
    local hdr, err = con:readfull(7, 1)
    assert(hdr, err)

    local tid, pid, len, uid = str_unpack('>I2I2I2I1', hdr)
    local pdu

    pdu, err = con:readfull(len - 1, 1)
    assert(pdu, err)

    return tid, pid, uid, pdu
end

local function start_custom_server(handler)
    local srv, err = socket.listen_tcp('127.0.0.1', 0)
    assert(srv, err)

    local port = srv:getsockname().port

    eco.run(function()
        local con = srv:accept(1)
        if not con then
            return
        end

        handler(con)
        con:close()
    end)

    return srv, port
end

test.run_case_sync('modbus tcp loopback', function()
    local state = {
        coils = {},
        discrete_inputs = { [0] = true, [2] = true, [9] = true },
        holding_registers = {},
        input_registers = { [0] = 100, [1] = 200, [2] = 0xFFFF }
    }

    local srv, port = start_mock_server(state)

    local c = modbus.new_tcp_client({ ipaddr = '127.0.0.1', port = port, timeout = 3.0 })

    local ok, err = c:connect()
    assert(ok, err)
    assert(c:connected() == true)

    -- idempotent connect
    assert(c:connect() == true)

    -- read discrete inputs preset by the slave
    local values
    values, err = c:read_discrete_inputs(0, 10)
    assert(values, err)
    assert(#values == 10)
    assert(values[1] == true and values[2] == false and values[3] == true)
    assert(values[10] == true)

    -- read input registers preset by the slave
    values, err = c:read_input_registers(0, 3)
    assert(values, err)
    assert(values[1] == 100 and values[2] == 200 and values[3] == 0xFFFF)

    -- default quantity is 1
    values, err = c:read_input_registers(1)
    assert(values, err)
    assert(#values == 1 and values[1] == 200)

    -- write and read back a single register
    ok, err = c:write_single_register(10, 0x1234)
    assert(ok, err)

    values, err = c:read_holding_registers(10, 1)
    assert(values, err)
    assert(values[1] == 0x1234)

    -- write and read back multiple registers
    ok, err = c:write_multiple_registers(20, { 1, 2, 3, 0xFFFF })
    assert(ok, err)

    values, err = c:read_holding_registers(20, 4)
    assert(values, err)
    assert(values[1] == 1 and values[2] == 2 and values[3] == 3 and values[4] == 0xFFFF)

    -- write and read back a single coil
    ok, err = c:write_single_coil(5, true)
    assert(ok, err)

    values, err = c:read_coils(5, 1)
    assert(values, err)
    assert(values[1] == true)

    -- write and read back multiple coils
    ok, err = c:write_multiple_coils(0, { true, false, true, true, false, false, true, true, true })
    assert(ok, err)

    values, err = c:read_coils(0, 9)
    assert(values, err)
    assert(values[1] == true and values[2] == false and values[3] == true and values[4] == true)
    assert(values[5] == false and values[6] == false and values[7] == true and values[8] == true)
    assert(values[9] == true)

    -- quantity defaults to 1
    values, err = c:read_coils(0)
    assert(values and values[1] == true and #values == 1)

    c:close()
    assert(c:connected() == false)

    -- idempotent close
    c:close()

    values, err = c:read_coils(0, 1)
    assert(values == nil and err == 'unconnected')

    srv:close()
end)

test.run_case_sync('modbus tcp exception response', function()
    local state = {
        coils = {},
        discrete_inputs = {},
        holding_registers = {},
        input_registers = {}
    }

    local srv, port = start_mock_server(state)

    local c = modbus.new_tcp_client({ ipaddr = '127.0.0.1', port = port })

    local ok, err = c:connect()
    assert(ok, err)

    -- the mock slave rejects addresses >= 0x8000
    local values, code
    values, err, code = c:read_holding_registers(0x8000, 1)
    assert(values == nil)
    assert(code == modbus.EXCEPTION_ILLEGAL_DATA_ADDRESS)
    assert(err == 'modbus exception: illegal data address')

    -- the connection stays usable after an exception response
    ok, err = c:write_single_register(1, 42)
    assert(ok, err)

    values, err = c:read_holding_registers(1, 1)
    assert(values and values[1] == 42)

    c:close()
    srv:close()
end)

test.run_case_sync('modbus tcp connect failure', function()
    local c = modbus.new_tcp_client({ ipaddr = '127.0.0.1', port = 1, timeout = 1.0 })

    local ok, err = c:connect()
    assert(ok == nil)
    assert(type(err) == 'string')
    assert(err:find('network:', 1, true))

    c:close()
end)

test.run_case_sync('modbus tcp mismatched transaction closes connection', function()
    local srv, port = start_custom_server(function(con)
        local tid, pid, uid = read_tcp_request(con)
        local pdu = '\x03\x02\x00\x2A'

        con:send(str_pack('>I2I2I2I1', (tid + 1) & 0xFFFF,
                          pid, #pdu + 1, uid) .. pdu)
    end)
    local c = modbus.new_tcp_client({ ipaddr = '127.0.0.1', port = port })

    assert(c:connect())

    local values, err = c:read_holding_registers(0, 1)
    assert(values == nil and err == 'transaction id mismatch')
    assert(c:connected() == false)

    c:close()
    srv:close()
end)

test.run_case_sync('modbus tcp malformed PDU closes connection', function()
    local srv, port = start_custom_server(function(con)
        local tid, pid, uid = read_tcp_request(con)
        local pdu = '\x03\x02\x00\x2A'

        -- Deliberately under-report the PDU length, leaving two bytes in stream.
        con:send(str_pack('>I2I2I2I1', tid, pid, 3, uid) .. pdu)
    end)
    local c = modbus.new_tcp_client({ ipaddr = '127.0.0.1', port = port })

    assert(c:connect())

    local values, err = c:read_holding_registers(0, 1)
    assert(values == nil and err:find('byte count', 1, true))
    assert(c:connected() == false)

    c:close()
    srv:close()
end)

test.run_case_sync('modbus tcp rejects oversized MBAP length', function()
    local srv, port = start_custom_server(function(con)
        local tid, pid, uid = read_tcp_request(con)

        con:send(str_pack('>I2I2I2I1', tid, pid, 255, uid))
    end)
    local c = modbus.new_tcp_client({ ipaddr = '127.0.0.1', port = port })

    assert(c:connect())

    local values, err = c:read_holding_registers(0, 1)
    assert(values == nil and err == 'malformed response: invalid MBAP header')
    assert(c:connected() == false)

    c:close()
    srv:close()
end)

test.run_case_sync('modbus tcp timeout is an absolute deadline', function()
    local srv, port = start_custom_server(function(con)
        local tid, pid, uid = read_tcp_request(con)
        local pdu = '\x03\x02\x00\x2A'
        local adu = str_pack('>I2I2I2I1', tid, pid, #pdu + 1, uid) .. pdu

        for i = 1, #adu do
            local ok = con:send(adu:sub(i, i))
            if not ok then
                return
            end

            time.sleep(0.08)
        end
    end)
    local c = modbus.new_tcp_client({
        ipaddr = '127.0.0.1',
        port = port,
        timeout = 0.1
    })

    assert(c:connect())

    local started = time.monotonic()
    local values, err = c:read_holding_registers(0, 1)
    local elapsed = time.monotonic() - started

    assert(values == nil and err == 'network: timeout')
    assert(elapsed < 0.3, str_fmt('transaction exceeded deadline: %.3f', elapsed))
    assert(c:connected() == false)

    c:close()
    srv:close()
end)

test.run_case_sync('modbus tcp unit id is stable during transaction', function()
    local srv, port = start_custom_server(function(con)
        local tid, pid, uid = read_tcp_request(con)
        local pdu = '\x03\x02\x00\x2A'

        assert(uid == 1)
        time.sleep(0.05)
        con:send(str_pack('>I2I2I2I1', tid, pid, #pdu + 1, uid) .. pdu)
    end)
    local c = modbus.new_tcp_client({
        ipaddr = '127.0.0.1',
        port = port,
        unit_id = 1
    })
    local done = false
    local result
    local request_err

    assert(c:connect())

    eco.run(function()
        result, request_err = c:read_holding_registers(0, 1)
        done = true
    end)

    eco.run(function()
        time.sleep(0.01)
        c:set_unit_id(2)
    end)

    test.wait_until('modbus request with unit id snapshot', function()
        return done
    end, 1)

    assert(result and result[1] == 42, request_err)
    assert(c.unit_id == 2)

    c:close()
    srv:close()
end)

test.run_case_sync('modbus tcp accepts direct-server unit id', function()
    local srv, port = start_custom_server(function(con)
        local tid, pid = read_tcp_request(con)
        local pdu = '\x03\x02\x00\x2A'

        con:send(str_pack('>I2I2I2I1', tid, pid, #pdu + 1, 0xFF) .. pdu)
    end)
    local c = modbus.new_tcp_client({
        ipaddr = '127.0.0.1',
        port = port,
        unit_id = 1
    })

    assert(c:connect())

    local values, err = c:read_holding_registers(0, 1)
    assert(values and values[1] == 42, err)

    c:close()
    srv:close()
end)

test.run_case_sync('modbus tcp concurrent connect is idempotent', function()
    local srv, err = socket.listen_tcp('127.0.0.1', 0)
    assert(srv, err)

    local port = srv:getsockname().port
    local accepted = 0
    local server_done = false

    eco.run(function()
        local first = srv:accept(1)
        assert(first)
        accepted = accepted + 1

        local second = srv:accept(0.1)
        if second then
            accepted = accepted + 1
            second:close()
        end

        first:close()
        server_done = true
    end)

    local c = modbus.new_tcp_client({ ipaddr = '127.0.0.1', port = port })
    local completed = 0
    local errors = {}

    for i = 1, 2 do
        eco.run(function()
            local ok, connect_err = c:connect()

            if not ok then
                errors[#errors + 1] = connect_err
            end

            completed = completed + 1
        end)
    end

    test.wait_until('concurrent connect calls', function()
        return completed == 2 and server_done
    end, 1)

    assert(#errors == 0, errors[1])
    assert(accepted == 1, str_fmt('expected one connection, got %d', accepted))

    c:close()
    srv:close()
end)

test.run_case_sync('modbus tcp queued request does not cross reconnect', function()
    local srv, err = socket.listen_tcp('127.0.0.1', 0)
    assert(srv, err)

    local port = srv:getsockname().port
    local first_received = false

    eco.run(function()
        local first = assert(srv:accept(1))

        read_tcp_request(first)
        first_received = true
        first:readfull(1, 1)
        first:close()

        local second = assert(srv:accept(1))
        local tid, pid, uid = read_tcp_request(second)
        local pdu = '\x03\x02\x00\x2A'

        second:send(str_pack('>I2I2I2I1', tid, pid, #pdu + 1, uid) .. pdu)
        second:close()
    end)

    local c = modbus.new_tcp_client({ ipaddr = '127.0.0.1', port = port })
    local first_done = false
    local queued_done = false
    local first_err
    local queued_err
    local ignored

    assert(c:connect())

    eco.run(function()
        ignored, first_err = c:read_holding_registers(0, 1)
        first_done = true
    end)

    eco.run(function()
        ignored, queued_err = c:read_holding_registers(0, 1)
        queued_done = true
    end)

    test.wait_until('first request sent before reconnect', function()
        return first_received
    end, 1)

    c:close()
    assert(c:connect())

    test.wait_until('old generation requests completed', function()
        return first_done and queued_done
    end, 1)

    assert(first_err and first_err:find('network:', 1, true))
    assert(queued_err == 'network: connection changed')

    local values
    values, err = c:read_holding_registers(0, 1)
    assert(values and values[1] == 42, err)

    c:close()
    srv:close()
end)

print('modbus tests passed')
