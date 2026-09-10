-- SPDX-License-Identifier: MIT
-- Author: ziye.chen <ziye.chen@gl-inet.com>

--- Modbus RTU client (master) over a serial port.
--
-- The port uses the standard 11-bit RTU character format: even/odd parity
-- with one stop bit, or no parity with two stop bits. The receiver enforces
-- t1.5 between characters and waits for a continuous t3.5 idle interval
-- before transmitting. Address 0 is supported for write broadcasts only.
-- RS-485 adapters must provide automatic driver-direction control.
--
-- Read/write methods return a result on success, `(nil, err)` on transport or
-- protocol failure, and `(nil, err, code)` for a valid Modbus exception.
--
-- @module eco.modbus.rtu

local termios = require 'eco.termios'
local proto = require 'eco.modbus.proto'
local file = require 'eco.file'
local sync = require 'eco.sync'
local time = require 'eco.time'

local str_byte = string.byte
local str_char = string.char
local str_pack = string.pack
local str_unpack = string.unpack
local str_fmt = string.format

local M = {}

local DEFAULT_BAUD = 9600
local DEFAULT_PARITY = 'E'
local DEFAULT_TIMEOUT = 1.0
local DEFAULT_BROADCAST_DELAY = 0.1
local MAX_RTU_DATA_LENGTH = 250
local SCHEDULER_TIMEOUT_GUARD = 0.002

local baud_rates = {
    [50] = 'B50',
    [75] = 'B75',
    [110] = 'B110',
    [134] = 'B134',
    [150] = 'B150',
    [200] = 'B200',
    [300] = 'B300',
    [600] = 'B600',
    [1200] = 'B1200',
    [1800] = 'B1800',
    [2400] = 'B2400',
    [4800] = 'B4800',
    [9600] = 'B9600',
    [19200] = 'B19200',
    [38400] = 'B38400',
    [57600] = 'B57600',
    [115200] = 'B115200',
    [230400] = 'B230400'
}

--- Modbus RTU client object.
-- @type client

local methods = {}

local function is_finite_positive(value)
    return type(value) == 'number' and value > 0 and value < math.huge
end

local function check_option(name, value)
    assert(type(name) == 'string')

    if name == 'device' then
        assert(value == nil or type(value) == 'string',
               'expecting device to be a string')
    elseif name == 'baud' then
        assert(value == nil or baud_rates[value], 'expecting a supported baud rate')
    elseif name == 'parity' then
        assert(value == nil or value == 'N' or value == 'E' or value == 'O',
               "expecting parity to be one of 'N', 'E', 'O'")
    elseif name == 'stop_bits' then
        assert(value == nil or value == 1 or value == 2,
               'expecting stop_bits to be 1 or 2')
    elseif name == 'unit_id' then
        if value ~= nil then
            proto.check_rtu_unit_id(value)
        end
    elseif name == 'timeout' or name == 'broadcast_delay' then
        assert(value == nil or is_finite_positive(value),
               'expecting ' .. name .. ' to be a finite positive number')
    end
end

local function frame_interval(baud)
    if baud > 19200 then
        return 0.00175
    end

    return 3.5 * 11 / baud
end

local function character_interval(baud)
    if baud > 19200 then
        return 0.00075
    end

    return 1.5 * 11 / baud
end

local function configure_port(fd, opts)
    local attr, err = termios.tcgetattr(fd)
    if not attr then
        return nil, err
    end

    local nattr = attr:clone()

    -- Binary/raw input. Parity error handling is selected below.
    nattr:clr_flag('l', termios.ECHO | termios.ECHONL | termios.ICANON |
                        termios.ISIG | termios.IEXTEN)
    nattr:clr_flag('i', termios.IGNBRK | termios.BRKINT | termios.IGNPAR |
                        termios.PARMRK | termios.INPCK | termios.ISTRIP |
                        termios.INLCR | termios.IGNCR | termios.ICRNL |
                        termios.IUCLC | termios.IXON | termios.IXANY |
                        termios.IXOFF)
    nattr:clr_flag('o', termios.OPOST)

    -- Reset all format/flow-control bits before selecting the RTU format.
    nattr:clr_flag('c', termios.CSIZE | termios.CSTOPB | termios.PARENB |
                        termios.PARODD | termios.CMSPAR | termios.CRTSCTS)
    nattr:set_flag('c', termios.CS8 | termios.CREAD | termios.CLOCAL)

    if opts.parity == 'E' then
        nattr:set_flag('c', termios.PARENB)
        nattr:set_flag('i', termios.INPCK)
    elseif opts.parity == 'O' then
        nattr:set_flag('c', termios.PARENB | termios.PARODD)
        nattr:set_flag('i', termios.INPCK)
    else
        nattr:set_flag('c', termios.CSTOPB)
    end

    nattr:set_cc(termios.VMIN, 1)
    nattr:set_cc(termios.VTIME, 0)

    local ok, serr = nattr:set_speed(termios[baud_rates[opts.baud]])
    if not ok then
        return nil, serr
    end

    ok, serr = termios.tcsetattr(fd, termios.TCSANOW, nattr)
    if not ok then
        return nil, serr
    end

    return attr
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

    local left = self.timeout - (time.monotonic() - started)
    if left <= 0 then
        self.mutex:unlock()
        return nil, nil, 'timeout'
    end

    return epoch, left
end

local function restore_and_close(self, f)
    if self.file == f then
        self.file = nil
        self.saved_attr = nil
    end

    f:close()
end

--- Open and configure the serial port.
function methods:open()
    local epoch, _, err = lock_client(self)
    if epoch == nil then
        return nil, err
    end

    if self.file then
        self.mutex:unlock()
        return true
    end

    local opts = self.opts
    local f

    f, err = file.open(opts.device, file.O_RDWR | file.O_NOCTTY | file.O_NONBLOCK)
    if not f then
        self.mutex:unlock()
        return nil, err
    end

    local attr
    attr, err = configure_port(f.fd, opts)
    if not attr then
        f:close()
        self.mutex:unlock()
        return nil, err
    end

    if epoch ~= self.epoch then
        termios.tcsetattr(f.fd, termios.TCSANOW, attr)
        f:close()
        self.mutex:unlock()
        return nil, 'connection changed'
    end

    self.file = f
    self.saved_attr = attr
    f.before_close = function(fd)
        termios.tcsetattr(fd, termios.TCSANOW, attr)
    end
    self.mutex:unlock()

    return true
end

--- Close the port, restore its attributes and cancel an in-flight request.
function methods:close()
    local f = self.file

    self.epoch = self.epoch + 1

    if f then
        restore_and_close(self, f)
    end
end

--- Check whether the serial port is open.
-- @treturn boolean
function methods:opened()
    return self.file ~= nil
end

--- Set the unit identifier used by transactions that start subsequently.
-- @tparam integer unit_id Unit identifier (0 - 247); 0 is write broadcast.
function methods:set_unit_id(unit_id)
    proto.check_rtu_unit_id(unit_id)
    self.unit_id = unit_id
end

local function remaining(deadline)
    return deadline - time.monotonic()
end

local function wait_bus_idle(f, silence, deadline)
    while true do
        local left = remaining(deadline)
        if left <= 0 then
            return nil, 'timeout waiting for an idle bus'
        end

        local wait = math.min(left, silence)
        -- eco's generic scheduler has millisecond resolution and rounds its
        -- current timestamp down. Keep the compensation local to RTU instead
        -- of changing timeout behavior for every eco user.
        local data, err = f:read(256, wait + SCHEDULER_TIMEOUT_GUARD)

        if not data then
            if err == 'timeout' and wait >= silence then
                return true
            elseif err == 'timeout' then
                return nil, 'timeout waiting for an idle bus'
            end

            return nil, err
        end

        -- Stale/noise bytes were discarded; restart the silent interval.
    end
end

local function arm_timeout(f, timeout)
    local guard = { expired = false }
    local timer, err = time.at(timeout, function(tmr)
        guard.expired = true
        f.rd:cancel()
        f.wr:cancel()
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

local function read_byte(f, deadline, max_gap)
    local left = remaining(deadline)
    if left <= 0 then
        return nil, 'timeout'
    end

    local timeout = max_gap and math.min(left, max_gap) or left
    local started = time.monotonic()
    local data, err = f:read(1, timeout + SCHEDULER_TIMEOUT_GUARD)

    if not data then
        if err == 'timeout' and max_gap and left > max_gap then
            return nil, 'inter-character timeout'
        end

        return nil, err
    end

    if max_gap and time.monotonic() - started > max_gap then
        return nil, 'inter-character timeout'
    end

    return data
end

local function read_bytes(f, count, deadline, max_gap)
    local bytes = {}

    for i = 1, count do
        local byte, err = read_byte(f, deadline, max_gap)
        if not byte then
            return nil, err
        end

        bytes[i] = byte
    end

    return table.concat(bytes)
end

local function is_read_function(fc)
    return fc == proto.FC_READ_COILS or fc == proto.FC_READ_DISCRETE_INPUTS or
           fc == proto.FC_READ_HOLDING_REGISTERS or
           fc == proto.FC_READ_INPUT_REGISTERS
end

local function read_response(self, f, fc, unit_id, request_frame,
                             deadline, earliest_response)
    local address, err = read_byte(f, deadline)
    if not address then
        return nil, err
    end

    if time.monotonic() < earliest_response then
        local echo_tail
        echo_tail, err = read_bytes(f, #request_frame - 1, deadline,
                                    self.character_interval)

        if echo_tail and address .. echo_tail == request_frame then
            return false, 'local echo'
        end

        if not echo_tail then
            return nil, err
        end

        return nil, 'response started before the required t3.5 interval'
    end

    local function_code
    function_code, err = read_byte(f, deadline, self.character_interval)
    if not function_code then
        return nil, err
    end

    local addr = str_byte(address)
    local rfc = str_byte(function_code)
    local body

    if rfc == (fc | 0x80) then
        body, err = read_bytes(f, 3, deadline, self.character_interval)
    elseif rfc ~= fc then
        return nil, str_fmt('unexpected function code in response: 0x%02x '
                            .. '(expecting 0x%02x)', rfc, fc)
    elseif is_read_function(fc) then
        local count
        count, err = read_byte(f, deadline, self.character_interval)
        if not count then
            return nil, err
        end

        local byte_count = str_byte(count)
        if byte_count > MAX_RTU_DATA_LENGTH then
            return nil, 'malformed response: byte count exceeds RTU limit'
        end

        local data
        data, err = read_bytes(f, byte_count + 2, deadline,
                               self.character_interval)
        if data then
            body = count .. data
        end
    else
        body, err = read_bytes(f, 6, deadline, self.character_interval)
    end

    if not body then
        return nil, err
    end

    local frame = address .. function_code .. body
    local actual_crc = str_unpack('<I2', frame, #frame - 1)
    local expected_crc = proto.crc16(frame:sub(1, -3))

    if actual_crc ~= expected_crc then
        return nil, 'invalid CRC in response'
    end

    if addr ~= unit_id then
        return nil, 'unit id mismatch'
    end

    return frame:sub(2, -3)
end

local function sleep_until(deadline, canceled)
    while true do
        local delay = remaining(deadline)
        if delay <= 0 then
            return true
        end

        time.sleep(math.min(delay, 0.01))

        if canceled() then
            return nil
        end
    end
end

local function finish_transaction(self, guard)
    stop_timeout(guard)
    self.mutex:unlock()
end

local function transact(self, fc, pdu, decoder, is_write)
    local epoch, acquire_timeout, err = lock_client(self)
    if epoch == nil then
        return nil, 'serial: ' .. err
    end

    local f = self.file
    if not f then
        self.mutex:unlock()
        return nil, 'not opened'
    end

    local unit_id = self.unit_id
    if unit_id == 0 and not is_write then
        self.mutex:unlock()
        return nil, 'broadcast address is only valid for write requests'
    end

    local idle_deadline = time.monotonic() + acquire_timeout
    local ok

    ok, err = wait_bus_idle(f, self.frame_interval, idle_deadline)
    if not ok then
        self.mutex:unlock()
        return nil, 'serial: ' .. err
    end

    if epoch ~= self.epoch or self.file ~= f then
        self.mutex:unlock()
        return nil, 'serial: connection changed'
    end

    local request = str_char(unit_id) .. pdu
    local frame = request .. str_pack('<I2', proto.crc16(request))
    local tx_started = time.monotonic()
    local tx_duration = #frame * self.character_time
    local wait_timeout = is_write and unit_id == 0 and
                         math.max(self.timeout, self.broadcast_delay) or self.timeout
    local operation_timeout = tx_duration + wait_timeout + self.frame_interval
    local guard

    guard, err = arm_timeout(f, operation_timeout)
    if not guard then
        self.mutex:unlock()
        return nil, 'serial: ' .. err
    end

    ok, err = f:write(frame, operation_timeout)
    if not ok then
        local message = guard.expired and 'timeout' or (err or 'write failed')

        finish_transaction(self, guard)
        return nil, 'serial: ' .. message
    end

    if unit_id == 0 then
        local waited = sleep_until(tx_started + tx_duration + self.broadcast_delay,
                                   function()
            return guard.expired or epoch ~= self.epoch or self.file ~= f
        end)

        local changed = epoch ~= self.epoch or self.file ~= f
        local expired = guard.expired
        finish_transaction(self, guard)

        if changed then
            return nil, 'serial: connection changed'
        elseif not waited or expired then
            return nil, 'serial: timeout'
        end

        return true
    end

    local earliest_response = tx_started + tx_duration + self.frame_interval
    local response_deadline = earliest_response + self.timeout
    local response

    repeat
        response, err = read_response(self, f, fc, unit_id, frame,
                                      response_deadline, earliest_response)
    until response ~= false
    if not response then
        local message = guard.expired and 'timeout' or (err or 'read failed')

        finish_transaction(self, guard)
        return nil, 'serial: ' .. message
    end

    if epoch ~= self.epoch or self.file ~= f then
        finish_transaction(self, guard)
        return nil, 'serial: connection changed'
    end

    local normal, exception_err, exception_code = proto.check_exception(fc, response)
    if not normal then
        finish_transaction(self, guard)

        if exception_code then
            return nil, exception_err, exception_code
        end

        return nil, exception_err
    end

    local result
    result, err = decoder(response)

    finish_transaction(self, guard)

    return result, err
end

local function read_bits(self, fc, address, quantity)
    quantity = quantity or 1

    local pdu = proto.pack_read_bits_request(fc, address, quantity)

    return transact(self, fc, pdu, function(response)
        return proto.unpack_read_bits_response(response, quantity)
    end, false)
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
    end, false)
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
    end, true)
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

--- Create a new Modbus RTU client.
-- @tparam table opts Options table.
-- @tparam string opts.device Serial port device path.
-- @tparam[opt=9600] integer opts.baud Baud rate.
-- @tparam[opt='E'] string opts.parity Parity: `'E'`, `'O'` or `'N'`.
-- @tparam[opt] integer opts.stop_bits One with parity, two without parity.
-- @tparam[opt=1] integer opts.unit_id Address 0 - 247; 0 is write broadcast.
-- @tparam[opt=1.0] number opts.timeout Transaction/response timeout in seconds.
-- @tparam[opt=0.1] number opts.broadcast_delay Broadcast turnaround delay.
-- @treturn client
function M.new(opts)
    assert(type(opts) == 'table', 'expecting opts to be a table')

    for name, value in pairs(opts) do
        check_option(name, value)
    end

    assert(opts.device ~= nil, 'expecting device')

    local baud = opts.baud or DEFAULT_BAUD
    local parity = opts.parity or DEFAULT_PARITY
    local stop_bits = opts.stop_bits

    if stop_bits == nil then
        stop_bits = parity == 'N' and 2 or 1
    end

    assert(parity == 'N' and stop_bits == 2 or
           parity ~= 'N' and stop_bits == 1,
           'expecting one stop bit with parity or two stop bits without parity')

    return setmetatable({
        opts = {
            device = opts.device,
            baud = baud,
            parity = parity,
            stop_bits = stop_bits
        },
        epoch = 0,
        unit_id = opts.unit_id == nil and 1 or opts.unit_id,
        timeout = opts.timeout or DEFAULT_TIMEOUT,
        broadcast_delay = opts.broadcast_delay or DEFAULT_BROADCAST_DELAY,
        character_time = 11 / baud,
        character_interval = character_interval(baud),
        frame_interval = frame_interval(baud),
        mutex = sync.mutex()
    }, metatable)
end

return M
