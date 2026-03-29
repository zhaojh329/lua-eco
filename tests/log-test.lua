#!/usr/bin/env eco

local file = require 'eco.file'
local log = require 'eco.log'
local sys = require 'eco.sys'
local test = require 'test'

local function contains(s, needle)
    return s and s:find(needle, 1, true) ~= nil
end

local function run_case(name, fn)
    local ok, err = pcall(fn)
    assert(ok, name .. ': ' .. tostring(err))
end

local pid = sys.getpid()
local base = string.format('/tmp/eco-log-test-%d', pid)
local path1 = base .. '-1.log'
local path2 = base .. '-2.log'
local path3 = base .. '-3.log'
local stress_path = base .. '-stress.log'
local roll_path = base .. '-roll.log'

os.remove(path1)
os.remove(path2)
os.remove(path3)
os.remove(stress_path)
os.remove(roll_path)

local function remove_rolled(path)
    local dir = '/tmp'
    local name = path:match('([^/]+)$') or path
    local prefix = name .. '.'

    for n in file.dir(dir) do
        if n:sub(1, #prefix) == prefix then
            os.remove(dir .. '/' .. n)
        end
    end
end

local function count_rolled(path)
    local dir = '/tmp'
    local name = path:match('([^/]+)$') or path
    local prefix = name .. '.'
    local n = 0

    for entry in file.dir(dir) do
        if entry:sub(1, #prefix) == prefix then
            n = n + 1
        end
    end

    return n
end

remove_rolled(roll_path)

-- Constants should be exported as integers.
assert(math.type(log.EMERG) == 'integer')
assert(math.type(log.ALERT) == 'integer')
assert(math.type(log.CRIT) == 'integer')
assert(math.type(log.ERR) == 'integer')
assert(math.type(log.WARNING) == 'integer')
assert(math.type(log.NOTICE) == 'integer')
assert(math.type(log.INFO) == 'integer')
assert(math.type(log.DEBUG) == 'integer')
assert(math.type(log.FLAG_LF) == 'integer')
assert(math.type(log.FLAG_FILE) == 'integer')
assert(math.type(log.FLAG_PATH) == 'integer')

-- Argument validation for checked APIs.
test.expect_error(function()
    log.set_level('x')
end, 'set_level should reject non-integer level')

test.expect_error(function()
    log.set_path(false)
end, 'set_path should reject non-string path')

test.expect_error(function()
    log.set_ident(false)
end, 'set_ident should reject non-string ident')

test.expect_error(function()
    log.set_flags('x')
end, 'set_flags should reject non-integer flags')

test.expect_error(function()
    log.set_roll_size('x')
end, 'set_roll_size should reject non-integer size')

test.expect_error(function()
    log.set_roll_size(-1)
end, 'set_roll_size should reject negative size')

test.expect_error(function()
    log.set_roll_count('x')
end, 'set_roll_count should reject non-integer count')

test.expect_error(function()
    log.log('x', 'bad-priority')
end, 'log(priority, ...) should reject non-integer priority')

run_case('level filter and value rendering', function()
    log.set_ident('eco-log-test')
    log.set_path(path1)
    log.set_flags(log.FLAG_LF)
    log.set_level(log.INFO)

    log.debug('debug-filtered')
    log.info('info-line', 123, true, nil, { x = 1 })
    log.err('err-line')

    local data = assert(file.readfile(path1), 'failed to read log file')

    assert(not contains(data, 'debug-filtered'), 'debug log should be filtered at INFO level')
    assert(contains(data, 'info-line 123 true nil'), 'supported value types should be rendered')
    assert(not contains(data, 'table:'), 'unsupported value types should be ignored')
    assert(contains(data, 'err-line'), 'err line should be written')
end)

run_case('log() custom priority', function()
    log.set_level(log.DEBUG)
    log.log(log.WARNING, 'warn-line')

    local data = assert(file.readfile(path1), 'failed to read log file after warn log')
    assert(contains(data, 'warn-line'), 'log(priority, ...) should write warning message')
end)

run_case('flags file/path location', function()
    log.set_flags(log.FLAG_LF | log.FLAG_FILE)
    log.info('with-file-flag')

    local data = assert(file.readfile(path1), 'failed to read file-flag log output')
    assert(contains(data, 'with-file-flag'))
    assert(contains(data, 'log-test.lua'), 'FLAG_FILE should include source filename')

    log.set_flags(log.FLAG_LF | log.FLAG_PATH)
    log.info('with-path-flag')

    data = assert(file.readfile(path1), 'failed to read path-flag log output')
    assert(contains(data, 'with-path-flag'))
    assert(contains(data, 'log-test.lua'), 'FLAG_PATH should include source path information')
end)

run_case('path switch and lf flag behavior', function()
    log.set_path(path2)
    log.set_flags(0)
    log.set_level(log.DEBUG)

    log.info('noln')

    local data2 = assert(file.readfile(path2), 'failed to read path2')
    assert(contains(data2, 'noln'))
    assert(not contains(data2, 'noln\n'), 'FLAG_LF disabled should not append newline')

    log.set_flags(log.FLAG_LF)
    log.info('withln')

    data2 = assert(file.readfile(path2), 'failed to read path2 after LF on')
    assert(contains(data2, 'withln\n'), 'FLAG_LF enabled should append newline')

    -- Route to a third file and verify new writes do not go to previous path.
    local old_size = #data2

    log.set_path(path3)
    log.info('third-path-line')

    local data3 = assert(file.readfile(path3), 'failed to read path3')
    assert(contains(data3, 'third-path-line'))

    local data2_after = assert(file.readfile(path2), 'failed to read path2 after switch')
    assert(#data2_after == old_size, 'set_path should switch output destination immediately')
end)

run_case('long ident should be safe', function()
    log.set_path(path1)
    log.set_flags(log.FLAG_LF)
    log.set_level(log.INFO)

    log.set_ident(string.rep('x', 256))
    log.info('long-ident-line')

    local data = assert(file.readfile(path1), 'failed to read log output for long ident')
    assert(contains(data, 'long-ident-line'))
end)

run_case('stress memory plateau', function()
    local function burst(rounds, n)
        for _ = 1, rounds do
            for i = 1, n do
                log.info('stress-line', i, false, nil)
            end
        end
    end

    log.set_path(stress_path)
    log.set_flags(log.FLAG_LF)
    log.set_level(log.INFO)

    local base_mem_kb = test.lua_mem_kb()

    burst(5, 500)
    local after_first_kb = test.lua_mem_kb()

    burst(5, 500)
    local after_second_kb = test.lua_mem_kb()

    local growth_first_kb = after_first_kb - base_mem_kb
    local growth_second_kb = after_second_kb - after_first_kb
    local plateau_limit_kb = math.max(128, growth_first_kb * 0.30)

    assert(growth_first_kb < 8192,
        string.format('unexpectedly large initial log memory growth: %.2f KB', growth_first_kb))

    assert(growth_second_kb <= plateau_limit_kb,
        string.format('log memory keeps growing across equal bursts: first %.2f KB, second %.2f KB (limit %.2f KB)',
            growth_first_kb, growth_second_kb, plateau_limit_kb))
end)

run_case('rolling APIs rotate and cap rolled files', function()
    log.set_path(roll_path)
    log.set_flags(log.FLAG_LF)
    log.set_level(log.INFO)
    log.set_roll_size(256)
    log.set_roll_count(2)

    for i = 1, 200 do
        log.info('rolling-line', i, string.rep('x', 40))
    end

    local rolled = count_rolled(roll_path)
    assert(rolled > 0, 'should generate rolled files when size threshold is reached')
    assert(rolled <= 2, string.format('rolled file count should be capped, got %d', rolled))

    local current = assert(file.readfile(roll_path), 'failed to read current rolling log file')
    assert(#current > 0, 'current rolling log should still receive writes')

    log.set_roll_size(0)
end)

-- Reset output backend after test to avoid affecting other runs.
log.set_path('')
log.set_flags(log.FLAG_LF)
log.set_level(log.INFO)

os.remove(path1)
os.remove(path2)
os.remove(path3)
os.remove(stress_path)
os.remove(roll_path)
remove_rolled(roll_path)

print('log tests passed')
