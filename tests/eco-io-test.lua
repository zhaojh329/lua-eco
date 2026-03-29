#!/usr/bin/env eco

local socket = require 'eco.socket'
local eco = require 'eco'
local test = require 'test'
local file = require 'eco.file'

local function make_pair()
    local s1, s2 = socket.socketpair(socket.AF_UNIX, socket.SOCK_STREAM)
    assert(s1 and s2, s2)
    return s1, s2
end

local function close_pair(s1, s2)
    if s1 then
        pcall(function()
            s1:close()
        end)
    end

    if s2 then
        pcall(function()
            s2:close()
        end)
    end
end

test.run_case_sync('io wait/read/timeout', function()
    local s1, s2 = make_pair()
    local io = eco.io(s1:getfd())
    local rd = eco.reader(s1:getfd())

    eco.run(function()
        test.expect_error_contains(function()
            io:wait(0, 0.1)
        end, 'invalid', 'io:wait should reject zero event mask')

        test.expect_error_contains(function()
            io:wait(eco.READ | 0x100, 0.1)
        end, 'invalid', 'io:wait should reject unsupported event bits')

        local ok, err = io:wait(eco.WRITE, 0.2)
        assert(ok == true, err)

        local n, werr = s2:send('A')
        assert(n == 1, werr)

        ok, err = io:wait(eco.READ, 0.2)
        assert(ok == true, err)

        local data
        data, err = rd:readfull(1, 0.2)
        assert(data == 'A', err)

        ok, err = io:wait(eco.READ, 0.03)
        assert(ok == nil and err == 'timeout', 'io:wait should timeout on unreadable fd')

        close_pair(s1, s2)
    end)
end)

test.run_case_sync('reader readuntil streaming semantics', function()
    local s1, s2 = make_pair()
    local rd = eco.reader(s1:getfd())
    local wr = eco.writer(s2:getfd())

    eco.run(function()
        local chunk, found = rd:readuntil('END', 0.5)
        assert(chunk == 'ab')
        assert(found == nil, 'first readuntil call should return partial data without found flag')

        chunk, found = rd:readuntil('END', 0.5)
        assert(chunk == 'cdEF')
        assert(found == true)

        local tail, err = rd:read(4, 0.2)
        assert(tail == 'tail', err)

        close_pair(s1, s2)
    end)

    eco.run(function()
        local n, err = wr:write('abcd', 0.2)
        assert(n == 4, err)

        eco.sleep(0.01)

        n, err = wr:write('EFENDtail', 0.2)
        assert(n == 9, err)
    end)
end)

test.run_case_sync('io cancel and busy check', function()
    local s1, s2 = make_pair()
    local io = eco.io(s1:getfd())
    local canceled = false

    eco.run(function()
        local ok, err = io:wait(eco.READ, 1.0)
        assert(ok == nil and err == 'canceled', 'io:cancel should wake waiter with canceled')
        canceled = true
    end)

    eco.run(function()
        eco.sleep(0.01)

        local ok, perr = pcall(function()
            io:wait(eco.READ, 0.2)
        end)

        assert(not ok, 'second wait on same io should throw busy error')
        assert(tostring(perr):find('already waiting'), 'busy error message mismatch')

        io:cancel()
    end)

    eco.run(function()
        test.wait_until('io wait coroutine should be canceled', function()
            return canceled
        end, 1.0, 0.01)
        close_pair(s1, s2)
    end)
end)

test.run_case_sync('reader formats and readuntil', function()
    local s1, s2 = make_pair()
    local rd = eco.reader(s1:getfd())
    local wr = eco.writer(s2:getfd())

    eco.run(function()
        -- Format validation should fail before touching I/O state.
        test.expect_error_contains(function()
            rd:read('*x', 0.2)
        end, 'invalid format', 'reader:read should reject unknown format')

        test.expect_error_contains(function()
            rd:read('*ll', 0.2)
        end, 'invalid format', 'reader:read should reject multi-char format')

        test.expect_error_contains(function()
            rd:read(0, 0.2)
        end, 'expected size must be greater than 0', 'reader:read should reject non-positive size')

        test.expect_error_contains(function()
            rd:read(false, 0.2)
        end, 'invalid format', 'reader:read should reject non-string/non-integer format')

        local payload = 'hello\nworld\r\nbyeENDtail'
        local n, err = wr:write(payload, 0.2)
        assert(n == #payload, err)

        local line = rd:read('*l', 0.2)
        assert(line == 'hello')

        local line_keep = rd:read('*L', 0.2)
        assert(line_keep == 'world\r\n')

        local chunk, found = rd:readuntil('END', 0.2)
        assert(chunk == 'bye')
        assert(found == true)

        local tail, terr = rd:read(4, 0.2)
        assert(tail == 'tail', terr)
        close_pair(s1, s2)
    end)
end)

test.run_case_sync('reader readfull exact and closed', function()
    local s1, s2 = make_pair()
    local rd = eco.reader(s1:getfd())
    local wr = eco.writer(s2:getfd())
    local readfull_done = false

    eco.run(function()
        test.expect_error_contains(function()
            rd:readfull(0, 0.2)
        end, 'size must be greater than 0', 'reader:readfull should reject non-positive size')

        local data, err = rd:readfull(6, 0.5)
        assert(data == 'abcdef', err)
        readfull_done = true

        local tail
        tail, err = rd:read('*a', 0.2)
        assert(tail == 'xyz', err)

        local eof
        eof, err = rd:read(1, 0.05)
        assert(eof == nil and err == 'closed')

        close_pair(s1, s2)
    end)

    eco.run(function()
        local n, err = wr:write('abc', 0.2)
        assert(n == 3, err)

        -- readfull must block until remaining bytes arrive.
        eco.sleep(0.01)

        n, err = wr:write('defxyz', 0.2)
        assert(n == 6, err)

        s2:close()
    end)

    eco.run(function()
        test.wait_until('reader:readfull did not complete exact read', function()
            return readfull_done
        end, 1.0, 0.01)

        close_pair(s1, s2)
    end)
end)

test.run_case_sync('reader wait timeout and cancel', function()
    local s1, s2 = make_pair()
    local rd = eco.reader(s1:getfd())
    local canceled = false

    eco.run(function()
        local ok, err = rd:wait(0.02)
        assert(ok == nil and err == 'timeout')

        local data, rerr = rd:read(1, 1.0)
        assert(data == nil and rerr == 'canceled')
        canceled = true
    end)

    eco.run(function()
        eco.sleep(0.06)
        rd:cancel()
    end)

    eco.run(function()
        test.wait_until('reader cancel scenario did not complete', function()
            return canceled
        end, 1.0, 0.01)
        close_pair(s1, s2)
    end)
end)

test.run_case_sync('writer wait/write/sendfile', function()
    local s1, s2 = make_pair()
    local wr = eco.writer(s1:getfd())
    local rd = eco.reader(s2:getfd())

    eco.run(function()
        local ok, err = wr:wait(0.2)
        assert(ok == true, err)

        local n = wr:write('hello', 0.2)
        assert(n == 5)

        local got = rd:readfull(5, 0.2)
        assert(got == 'hello')

        local path = os.tmpname()
        local f = assert(io.open(path, 'wb'))
        f:write('0123456789abcdef')
        f:close()

        n, err = wr:sendfile(path, 2, 5, 0.2)
        assert(n == 5, err)

        got = rd:readfull(5, 0.2)
        assert(got == '23456')

        n, err = wr:sendfile(path, 100, 1, 0.2)
        assert(n == nil and err == 'closed', 'writer:sendfile should return closed for socket writer when sendfile sends no data')

        os.remove(path)

        close_pair(s1, s2)
    end)
end)

test.run_case_sync('writer timeout under backpressure', function()
    local s1, s2 = make_pair()
    local wr = eco.writer(s1:getfd())

    eco.run(function()
        s1:setoption('sndbuf', 4096)
        local big = string.rep('x', 2 * 1024 * 1024)

        local n, err = wr:write(big, 0.05)
        assert(n == nil and err == 'timeout', 'writer:write should timeout under backpressure')

        close_pair(s1, s2)
    end)
end)

test.run_case_sync('writer cancel blocked write', function()
    local s1, s2 = make_pair()
    local wr = eco.writer(s1:getfd())
    local canceled = false

    eco.run(function()
        s1:setoption('sndbuf', 4096)
        local big = string.rep('y', 2 * 1024 * 1024)

        local n, err = wr:write(big, 1.0)
        assert(n == nil and err == 'canceled', 'writer:cancel should wake blocked write')
        canceled = true
    end)

    eco.run(function()
        eco.sleep(0.05)
        wr:cancel()
    end)

    eco.run(function()
        test.wait_until('writer cancel scenario did not complete', function()
            return canceled
        end, 1.0, 0.01)
        close_pair(s1, s2)
    end)
end)

test.run_case_sync('read io fairness', function()
    local s1, s2 = make_pair()

    local done = false

    eco.run(function()
        eco.sleep(0.001)
        local data = string.rep('1', 64 * 1000)
        s1:send(data)
        s1:close()

        while true do
            if not s2:read(1) then
                done = true
                break
            end
        end
    end)

    local tick = 0

    eco.run(function()
        while not done do
            eco.sleep(0.001)
            tick = tick + 1
        end

        assert(tick > 0, 'read io fairness fail, tick = ' .. tick)
    end)
end)

test.run_case_sync('regular file read io fairness', function()
    local path = os.tmpname()
    local f = assert(io.open(path, 'wb'))
    local payload = string.rep('r', 64 * 3000)

    f:write(payload)
    f:close()

    local rf, err = file.open(path, file.O_RDONLY)
    assert(rf, err)

    local done = false

    eco.run(function()
        while true do
            local chunk, rerr = rf:read(1, 0.2)
            if not chunk then
                assert(rerr == 'eof', rerr)
                break
            end
        end

        rf:close()
        done = true
    end)

    eco.run(function()
        test.wait_until('regular file read completion', function()
            return done
        end, 2.0, 0.001)
        os.remove(path)
    end)
end)

test.run_case_sync('regular file write io fairness', function()
    local path = os.tmpname()
    local wf, err = file.open(path,
            file.O_WRONLY | file.O_CREAT | file.O_TRUNC,
            file.S_IRUSR | file.S_IWUSR)

    assert(wf, err)

    local loops = 64 * 3000
    local done = false

    eco.run(function()
        for _ = 1, loops do
            local n, werr = wf:write('w', 0.2)
            assert(n == 1, werr)
        end

        wf:close()
        done = true
    end)

    eco.run(function()
        test.wait_until('regular file write completion', function()
            return done
        end, 2.0, 0.001)

        local st, serr = file.stat(path)
        assert(st and st.size == loops, serr or 'unexpected file size after regular file write fairness test')

        os.remove(path)
    end)
end)

test.run_case_sync('regular file sendfile fairness', function()
    local s1, s2 = make_pair()
    local wr = eco.writer(s1:getfd())
    local rd = eco.reader(s2:getfd())

    local path = os.tmpname()
    local f = assert(io.open(path, 'wb'))
    f:write('z')
    f:close()

    local loops = 64 * 200
    local sent_done = false
    local recv_done = false

    eco.run(function()
        for _ = 1, loops do
            local n, err = wr:sendfile(path, 0, 1, 1.0)
            assert(n == 1, err)
        end

        sent_done = true
    end)

    eco.run(function()
        for _ = 1, loops do
            local data, err = rd:readfull(1, 1.0)
            assert(data == 'z', err)
        end

        recv_done = true
    end)

    eco.run(function()
        test.wait_until('regular file sendfile completion', function()
            return sent_done and recv_done
        end, 2.0, 0.001)

        close_pair(s1, s2)
        os.remove(path)
    end)
end)

test.run_case_sync('regular file write fairness before loop', function()
    local workers = 16
    local loops = 64 * 4
    local finished = 0
    local states = {}

    for _ = 1, workers do
        local path = os.tmpname()
        local wf, err = file.open(path,
                file.O_WRONLY | file.O_CREAT | file.O_TRUNC,
                file.S_IRUSR | file.S_IWUSR)

        assert(wf, err)

        local st = {
            path = path,
            wf = wf,
            wrote = 0,
        }

        states[#states + 1] = st

        eco.run(function()
            for i = 1, loops do
                local n, werr = st.wf:write('p', 1.0)
                assert(n == 1, werr)
                st.wrote = i
            end

            st.wf:close()
            finished = finished + 1
        end)
    end

    local progressed = 0

    for _, st in ipairs(states) do
        if st.wrote > 0 and st.wrote < loops then
            progressed = progressed + 1
        end
    end

        assert(progressed + finished == workers,
            string.format('pre-loop worker state mismatch: progressed=%d finished=%d workers=%d',
                    progressed, finished, workers))

    eco.run(function()
        while finished < workers do
            eco.sleep(0.001)
        end

        for _, st in ipairs(states) do
            local fst, serr = file.stat(st.path)
            assert(fst and fst.size == loops,
                   serr or 'unexpected file size after pre-loop fairness test')
            os.remove(st.path)
        end
    end)
end)

print('eco io/reader/writer tests passed')

-- GC regression for io/reader/writer objects and their worker coroutine.
do
    local weak = setmetatable({}, { __mode = 'v' })
    local s1, s2 = make_pair()
    local io = eco.io(s1:getfd())
    local rd = eco.reader(s1:getfd())
    local wr = eco.writer(s2:getfd())
    local done = false

    weak.io = io
    weak.rd = rd
    weak.wr = wr

    eco.run(function()
        weak.co = coroutine.running()

        local n, err = wr:write('Z', 0.2)
        assert(n == 1, err)

        local data
        data, err = rd:readfull(1, 0.2)
        assert(data == 'Z', err)

        close_pair(s1, s2)

        io = nil
        rd = nil
        wr = nil
        s1 = nil
        s2 = nil
        done = true
    end)

    test.wait_until('io gc worker completes', function()
        return done
    end, 2.0)

    test.full_gc()
    assert(eco.count() <= 1, 'all worker coroutines should be cleaned after io gc regression')
    assert(weak.co == nil and weak.io == nil and weak.rd == nil and weak.wr == nil,
           'io/reader/writer objects and worker coroutine should be collectible')
end

-- Memory regression for repeated io/reader/writer bursts.
do
    local function io_burst(rounds, n)
        for _ = 1, rounds do
            local done = 0

            for _ = 1, n do
                local s1, s2 = make_pair()
                local rd = eco.reader(s1:getfd())
                local wr = eco.writer(s2:getfd())

                eco.run(function()
                    local sent, err = wr:write('ping', 0.2)
                    assert(sent == 4, err)

                    local data
                    data, err = rd:readfull(4, 0.2)
                    assert(data == 'ping', err)

                    close_pair(s1, s2)
                    done = done + 1
                end)
            end

            test.wait_until('io burst round completes', function()
                return done == n
            end, 5.0)
        end
    end

    local base_mem_kb = test.lua_mem_kb()

    io_burst(5, 2000)
    local after_first_kb = test.lua_mem_kb()

    io_burst(5, 2000)
    local after_second_kb = test.lua_mem_kb()

    local growth_first_kb = after_first_kb - base_mem_kb
    local growth_second_kb = after_second_kb - after_first_kb
    local plateau_limit_kb = math.max(128, growth_first_kb * 0.30)

    assert(growth_first_kb < 8192,
           string.format('unexpectedly large initial io memory growth: %.2f KB', growth_first_kb))

    assert(growth_second_kb <= plateau_limit_kb,
           string.format('io memory keeps growing across equal bursts: first %.2f KB, second %.2f KB (limit %.2f KB)',
                         growth_first_kb, growth_second_kb, plateau_limit_kb))
end

print('eco io/reader/writer gc+memory tests passed')
