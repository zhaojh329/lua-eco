-- SPDX-License-Identifier: MIT
-- Author: ziye.chen <ziye.chen@gl-inet.com>

--- Modbus TCP client (master).
--
-- Requests on one client are serialized. A timeout covers mutex wait, write,
-- MBAP reception, PDU reception and validation. Any malformed response closes
-- the connection so unread bytes cannot corrupt a later transaction.
--
-- Read/write methods return a result on success, `(nil, err)` on transport or
-- protocol failure, and `(nil, err, code)` for a valid Modbus exception.
--
-- @module eco.modbus.tcp

local socket = require 'eco.socket'
local proto = require 'eco.modbus.proto'
local sync = require 'eco.sync'
local time = require 'eco.time'

local str_char = string.char
local str_pack = string.pack
local str_unpack = string.unpack

local M = {}

local MBAP_PROTOCOL_ID = 0
local MAX_MBAP_LENGTH = 254
local DEFAULT_PORT = 502
local DEFAULT_UNIT_ID = 0xFF
local DEFAULT_TIMEOUT = 3.0

--- Modbus TCP client object.
-- @type client

local methods = {}

local function is_finite_positive(value)
    return type(value) == 'number' and value > 0 and value < math.huge
end

local function check_option(name, value)
    assert(type(name) == 'string')

    if name == 'ipaddr' then
        assert(value == nil or type(value) == 'string',
               'expecting ipaddr to be a string')
    elseif name == 'port' then
        assert(value == nil or math.type(value) == 'integer' and
               value >= 1 and value <= 0xFFFF,
               'expecting port to be an integer between 1 and 65535')
    elseif name == 'unit_id' then
        if value ~= nil then
            proto.check_tcp_unit_id(value)
        end
    elseif name == 'timeout' then
        assert(value == nil or is_finite_positive(value),
               'expecting timeout to be a finite positive number')
    elseif name == 'mark' then
        assert(value == nil or math.type(value) == 'integer',
               'expecting mark to be an integer')
    elseif name == 'device' then
        assert(value == nil or type(value) == 'string',
               'expecting device to be a string')
    end
end

local function lock_client(self)
    local epoch = self.epoch
    local started = time.monotonic()
    local ok, err = self.mutex:lock(self.timeout)

    if not ok then
        return nil, nil, err
    end

    if epoch ~= self.epoch then
        self.mutex:unlock()
        return nil, nil, 'connection changed'
    end

    local remaining = self.timeout - (time.monotonic() - started)
    if remaining <= 0 then
        self.mutex:unlock()
        return nil, nil, 'timeout'
    end

    return epoch, remaining
end

local function invalidate_socket(self, sock)
    if self.sock == sock then
        self.sock = nil
        self.epoch = self.epoch + 1
    end

    sock:close()
end

local function arm_timeout(sock, timeout)
    local guard = { expired = false }
    local timer, err = time.at(timeout, function(tmr)
        guard.expired = true
        sock:close()
        tmr:close()
    end)

    if not timer then
        return nil, err
    end

    guard.timer = timer

    return guard
end

local function stop_timeout(guard)
    if guard and guard.timer then
        guard.timer:close()
        guard.timer = nil
    end
end

local function fail_transaction(self, sock, guard, err)
    if guard and guard.expired then
        err = 'network: timeout'
    end

    stop_timeout(guard)
    invalidate_socket(self, sock)
    self.mutex:unlock()

    return nil, err
end

--- Connect to the server.
--
-- Concurrent calls are serialized. A close issued while connect is pending
-- cancels the new connection before it becomes visible.
--
-- @treturn boolean true On success.
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
function methods:connect()
    local epoch, remaining, err = lock_client(self)
    if epoch == nil then
        return nil, 'network: ' .. err
    end

    if self.sock then
        self.mutex:unlock()
        return true
    end

    local opts = self.opts
    local sock_opts = {
        connect_timeout = remaining,
        device = opts.device,
        mark = opts.mark
    }
    local sock

    sock, err = socket.connect_tcp(opts.ipaddr, opts.port, sock_opts)

    if not sock then
        self.mutex:unlock()
        return nil, 'network: ' .. err
    end

    if epoch ~= self.epoch then
        sock:close()
        self.mutex:unlock()
        return nil, 'network: connection changed'
    end

    self.sock = sock
    self.mutex:unlock()

    return true
end

--- Close the connection.
--
-- This method is idempotent and cancels an in-flight request.
function methods:close()
    local sock = self.sock

    self.epoch = self.epoch + 1
    self.sock = nil

    if sock then
        sock:close()
    end
end

--- Check whether the client has a connection object.
-- @treturn boolean
function methods:connected()
    return self.sock ~= nil
end

--- Set the unit identifier used by transactions that start subsequently.
-- @tparam integer unit_id Unit identifier (0 - 255).
function methods:set_unit_id(unit_id)
    proto.check_tcp_unit_id(unit_id)
    self.unit_id = unit_id
end

local function transact(self, fc, pdu, decoder)
    local epoch, remaining, err = lock_client(self)
    if epoch == nil then
        return nil, 'network: ' .. err
    end

    local sock = self.sock
    if not sock then
        self.mutex:unlock()
        return nil, 'unconnected'
    end

    local unit_id = self.unit_id
    local guard

    guard, err = arm_timeout(sock, remaining)
    if not guard then
        self.mutex:unlock()
        return nil, 'network: ' .. err
    end

    local tid = (self.tid + 1) & 0xFFFF
    self.tid = tid

    local mbap = str_pack('>I2I2I2', tid, MBAP_PROTOCOL_ID, #pdu + 1) ..
                 str_char(unit_id)
    local ok

    ok, err = sock:send(mbap .. pdu, remaining)
    if not ok then
        return fail_transaction(self, sock, guard,
                                'network: ' .. (err or 'write failed'))
    end

    local hdr
    hdr, err = sock:readfull(7, remaining)
    if not hdr then
        return fail_transaction(self, sock, guard,
                                'network: ' .. (err or 'read failed'))
    end

    local rtid, pid, len, uid = str_unpack('>I2I2I2I1', hdr)
    if pid ~= MBAP_PROTOCOL_ID or len < 2 or len > MAX_MBAP_LENGTH then
        return fail_transaction(self, sock, guard,
                                'malformed response: invalid MBAP header')
    end

    local data
    data, err = sock:readfull(len - 1, remaining)
    if not data then
        return fail_transaction(self, sock, guard,
                                'network: ' .. (err or 'read failed'))
    end

    if rtid ~= tid then
        return fail_transaction(self, sock, guard, 'transaction id mismatch')
    end

    -- A directly connected Modbus TCP server may return the non-significant
    -- Unit Identifier 0xFF. Gateway responses must echo the requested unit.
    if uid ~= unit_id and uid ~= 0xFF then
        return fail_transaction(self, sock, guard, 'unit id mismatch')
    end

    local normal, exception_err, exception_code = proto.check_exception(fc, data)
    if not normal then
        if exception_code then
            stop_timeout(guard)
            self.mutex:unlock()
            return nil, exception_err, exception_code
        end

        return fail_transaction(self, sock, guard, exception_err)
    end

    local result
    result, err = decoder(data)
    if result == nil then
        return fail_transaction(self, sock, guard, err)
    end

    stop_timeout(guard)
    self.mutex:unlock()

    return result
end

local function read_bits(self, fc, address, quantity)
    quantity = quantity or 1

    local pdu = proto.pack_read_bits_request(fc, address, quantity)

    return transact(self, fc, pdu, function(response)
        return proto.unpack_read_bits_response(response, quantity)
    end)
end

--- Read coils (function code 0x01).
-- @tparam integer address Starting address.
-- @tparam[opt=1] integer quantity Number of coils (1 - 2000).
-- @treturn[1] table Boolean values.
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
-- @treturn[2] integer Modbus exception code, when present.
function methods:read_coils(address, quantity)
    return read_bits(self, proto.FC_READ_COILS, address, quantity)
end

--- Read discrete inputs (function code 0x02).
-- @tparam integer address Starting address.
-- @tparam[opt=1] integer quantity Number of inputs (1 - 2000).
-- @treturn[1] table Boolean values.
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
-- @treturn[2] integer Modbus exception code, when present.
function methods:read_discrete_inputs(address, quantity)
    return read_bits(self, proto.FC_READ_DISCRETE_INPUTS, address, quantity)
end

local function read_registers(self, fc, address, quantity)
    quantity = quantity or 1

    local pdu = proto.pack_read_registers_request(fc, address, quantity)

    return transact(self, fc, pdu, function(response)
        return proto.unpack_read_registers_response(response, quantity)
    end)
end

--- Read holding registers (function code 0x03).
-- @tparam integer address Starting address.
-- @tparam[opt=1] integer quantity Number of registers (1 - 125).
-- @treturn[1] table Unsigned 16-bit register values.
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
-- @treturn[2] integer Modbus exception code, when present.
function methods:read_holding_registers(address, quantity)
    return read_registers(self, proto.FC_READ_HOLDING_REGISTERS, address, quantity)
end

--- Read input registers (function code 0x04).
-- @tparam integer address Starting address.
-- @tparam[opt=1] integer quantity Number of registers (1 - 125).
-- @treturn[1] table Unsigned 16-bit register values.
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
-- @treturn[2] integer Modbus exception code, when present.
function methods:read_input_registers(address, quantity)
    return read_registers(self, proto.FC_READ_INPUT_REGISTERS, address, quantity)
end

local function write_echo(self, fc, pdu, address, value)
    return transact(self, fc, pdu, function(response)
        return proto.unpack_write_echo_response(response, address, value)
    end)
end

--- Write a single coil (function code 0x05).
-- @tparam integer address Coil address.
-- @tparam boolean value Coil value.
-- @treturn[1] boolean true On success.
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
-- @treturn[2] integer Modbus exception code, when present.
function methods:write_single_coil(address, value)
    local fc = proto.FC_WRITE_SINGLE_COIL

    return write_echo(self, fc, proto.pack_write_single_coil_request(address, value),
                      address, value and 0xFF00 or 0x0000)
end

--- Write a single register (function code 0x06).
-- @tparam integer address Register address.
-- @tparam integer value Unsigned 16-bit value.
-- @treturn[1] boolean true On success.
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
-- @treturn[2] integer Modbus exception code, when present.
function methods:write_single_register(address, value)
    local fc = proto.FC_WRITE_SINGLE_REGISTER

    return write_echo(self, fc, proto.pack_write_single_register_request(address, value),
                      address, value)
end

--- Write multiple coils (function code 0x0F).
-- @tparam integer address Starting address.
-- @tparam table values Boolean values (1 - 1968 items).
-- @treturn[1] boolean true On success.
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
-- @treturn[2] integer Modbus exception code, when present.
function methods:write_multiple_coils(address, values)
    local fc = proto.FC_WRITE_MULTIPLE_COILS
    local pdu = proto.pack_write_multiple_coils_request(address, values)
    local quantity = str_unpack('>I2', pdu, 4)

    return write_echo(self, fc, pdu, address, quantity)
end

--- Write multiple registers (function code 0x10).
-- @tparam integer address Starting address.
-- @tparam table values Unsigned 16-bit values (1 - 123 items).
-- @treturn[1] boolean true On success.
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
-- @treturn[2] integer Modbus exception code, when present.
function methods:write_multiple_registers(address, values)
    local fc = proto.FC_WRITE_MULTIPLE_REGISTERS
    local pdu = proto.pack_write_multiple_registers_request(address, values)
    local quantity = str_unpack('>I2', pdu, 4)

    return write_echo(self, fc, pdu, address, quantity)
end

local metatable = {
    __index = methods,
    __close = methods.close,
    __gc = methods.close
}

--- Create a new Modbus TCP client.
-- @tparam table opts Options table.
-- @tparam string opts.ipaddr Numeric IPv4/IPv6 server address.
-- @tparam[opt=502] integer opts.port Server port (1 - 65535).
-- @tparam[opt=255] integer opts.unit_id Unit identifier (0 - 255).
-- @tparam[opt=3.0] number opts.timeout Transaction timeout in seconds.
-- @tparam[opt] integer opts.mark Set `SO_MARK` on the socket.
-- @tparam[opt] string opts.device Set `SO_BINDTODEVICE` on the socket.
-- @treturn client
function M.new(opts)
    assert(type(opts) == 'table', 'expecting opts to be a table')

    for name, value in pairs(opts) do
        check_option(name, value)
    end

    assert(opts.ipaddr ~= nil, 'expecting ipaddr')
    assert(socket.is_ipv4_address(opts.ipaddr) or socket.is_ipv6_address(opts.ipaddr),
           'expecting ipaddr to be a valid IPv4 or IPv6 address')

    return setmetatable({
        tid = 0,
        opts = {
            ipaddr = opts.ipaddr,
            port = opts.port or DEFAULT_PORT,
            mark = opts.mark,
            device = opts.device
        },
        epoch = 0,
        unit_id = opts.unit_id == nil and DEFAULT_UNIT_ID or opts.unit_id,
        timeout = opts.timeout or DEFAULT_TIMEOUT,
        mutex = sync.mutex()
    }, metatable)
end

return M
