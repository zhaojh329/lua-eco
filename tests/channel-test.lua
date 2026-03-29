#!/usr/bin/env eco

local eco = require 'eco'
local channel = require 'eco.channel'
local ifile = require 'eco.internal.file'
local test = require 'test'

-- Constructor argument checks and capacity normalization.
test.expect_error_contains(function()
    channel.new(1.5)
end, 'capacity must be an integer', 'channel.new should reject non-integer capacity')

test.run_case_async('channel capacity normalization and length', function()
    local ch_default = channel.new()
    assert(ch_default:length() == 0)

    local ok, err = ch_default:send('one', 0.1)
    assert(ok == true, err)

    ok, err = ch_default:send('two', 0.03)
    assert(ok == nil and err == 'timeout', 'default capacity should be 1')

    local ch_zero = channel.new(0)
    ok, err = ch_zero:send('one', 0.1)
    assert(ok == true, err)

    ok, err = ch_zero:send('two', 0.03)
    assert(ok == nil and err == 'timeout', 'capacity < 1 should normalize to 1')

    local ch_two = channel.new(2)
    assert(ch_two:length() == 0)

    assert(ch_two:send('a', 0.1))
    assert(ch_two:send('b', 0.1))
    assert(ch_two:length() == 2)

    ok, err = ch_two:send('c', 0.03)
    assert(ok == nil and err == 'timeout', 'capacity=2 channel should block on third send')

    local v = ch_two:recv(0.1)
    assert(v == 'a')
    assert(ch_two:length() == 1)

    v = ch_two:recv(0.1)
    assert(v == 'b')
    assert(ch_two:length() == 0)
end)

-- send() should block on full channel until recv() consumes one item.
test.run_case_sync('channel send blocks then unblocks', function()
    local ch = channel.new(1)
    local progressed = {
        sender_entered = false,
        sender_done = false,
        receiver_done = false
    }

    assert(ch:send('first', 0.1))

    eco.run(function()
        progressed.sender_entered = true
        local ok, err = ch:send('second', 1.0)
        assert(ok == true, err)
        progressed.sender_done = true
    end)

    eco.run(function()
        eco.sleep(0.02)

        local v, err = ch:recv(1.0)
        assert(v == 'first' and err == nil)

        v, err = ch:recv(1.0)
        assert(v == 'second' and err == nil)

        progressed.receiver_done = true
    end)

    eco.run(function()
        eco.sleep(0.01)
        assert(progressed.sender_entered == true)
        assert(progressed.sender_done == false, 'sender should still be blocked before receiver consumes')
    end)

    eco.run(function()
        eco.sleep(0.08)
        assert(progressed.sender_done == true)
        assert(progressed.receiver_done == true)
    end)
end)

-- recv() should block on empty channel until send() provides a value.
test.run_case_sync('channel recv blocks then unblocks', function()
    local ch = channel.new(1)
    local got

    eco.run(function()
        local v, err = ch:recv(1.0)
        assert(err == nil, err)
        got = v
    end)

    eco.run(function()
        eco.sleep(0.02)
        local ok, err = ch:send('payload', 1.0)
        assert(ok == true, err)
    end)

    eco.run(function()
        eco.sleep(0.08)
        assert(got == 'payload')
    end)
end)

-- Timeout behavior for send/recv.
test.run_case_async('channel send recv timeout', function()
    local ch = channel.new(1)

    local v, err = ch:recv(0.03)
    assert(v == nil and err == 'timeout')

    assert(ch:send('x', 0.1))

    local ok
    ok, err = ch:send('y', 0.03)
    assert(ok == nil and err == 'timeout')
end)

-- close() is idempotent, recv drains buffer, then recv returns nil.
test.run_case_sync('channel close drain and idempotent close', function()
    local ch = channel.new(3)

    assert(ch:send(1, 0.1))
    assert(ch:send(2, 0.1))
    assert(ch:length() == 2)

    ch:close()
    ch:close()

    local v, err = ch:recv(0.1)
    assert(v == 1 and err == nil)

    v, err = ch:recv(0.1)
    assert(v == 2 and err == nil)

    v, err = ch:recv(0.1)
    assert(v == nil and err == nil, 'closed+drained channel should return nil without timeout error')

    test.expect_error_contains(function()
        ch:send(3, 0.1)
    end, 'sending on closed channel', 'send on closed channel should throw')
end)

-- close() should wake blocked receivers; recv() then returns nil.
test.run_case_sync('channel close wakes blocked receiver', function()
    local ch = channel.new(1)
    local recv_done = false

    eco.run(function()
        local v, err = ch:recv(1.0)
        assert(v == nil and err == nil)
        recv_done = true
    end)

    eco.run(function()
        eco.sleep(0.02)
        ch:close()
    end)

    eco.run(function()
        eco.sleep(0.08)
        assert(recv_done == true)
    end)
end)

-- GC regression: channel wrapper and internal cond objects should be collectable.
do
    local weak = setmetatable({}, { __mode = 'v' })
    local send_fd, recv_fd

    test.run_case_sync('channel gc closes cond eventfd', function()
        local ch = channel.new(2)
        send_fd = ch.cond_send.efd
        recv_fd = ch.cond_recv.efd

        weak.ch = ch
    end)

    test.full_gc()

    assert(weak.ch == nil, 'channel should be collectible after references are dropped')

    local ok, err = ifile.close(send_fd)
    assert(ok == nil and type(err) == 'string', 'channel cond_send eventfd should be closed by GC path')

    ok, err = ifile.close(recv_fd)
    assert(ok == nil and type(err) == 'string', 'channel cond_recv eventfd should be closed by GC path')
end

-- Memory leak regression: equal channel bursts should show plateau behavior.
do
    test.full_gc()

    local function channel_burst(rounds, per_round)
        local total_received = 0

        for _ = 1, rounds do
            local round_target = total_received + per_round * 8

            for _ = 1, per_round do
                local ch = channel.new(4)

                eco.run(function()
                    for i = 1, 8 do
                        local ok, err = ch:send(i, 1.0)
                        assert(ok == true, err)
                    end

                    ch:close()
                end)

                eco.run(function()
                    while true do
                        local v, err = ch:recv(1.0)
                        assert(err == nil, err)

                        if v == nil then
                            break
                        end

                        total_received = total_received + 1
                    end
                end)
            end

            test.wait_until('channel burst round completes', function()
                return total_received == round_target
            end, 5.0)

            test.full_gc()
        end

        return total_received
    end

    local rounds = 8
    local per_round = 300
    local expected = rounds * per_round * 8

    local base_mem_kb = test.lua_mem_kb()

    assert(channel_burst(rounds, per_round) == expected)
    local after_first_kb = test.lua_mem_kb()

    assert(channel_burst(rounds, per_round) == expected)
    local after_second_kb = test.lua_mem_kb()

    local growth_first_kb = after_first_kb - base_mem_kb
    local growth_second_kb = after_second_kb - after_first_kb
    local plateau_limit_kb = math.max(128, growth_first_kb * 0.35)

    assert(growth_first_kb < 8192,
           string.format('unexpectedly large initial channel memory growth: %.2f KB', growth_first_kb))

    assert(growth_second_kb <= plateau_limit_kb,
           string.format('channel memory keeps growing across equal bursts: first %.2f KB, second %.2f KB (limit %.2f KB)',
                         growth_first_kb, growth_second_kb, plateau_limit_kb))
end

print('channel tests passed')
