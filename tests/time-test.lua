#!/usr/bin/env eco

local eco = require 'eco'
local time = require 'eco.time'
local ifile = require 'eco.internal.file'
local test = require 'test'

-- Constants and basic exported APIs.
assert(math.type(time.CLOCK_MONOTONIC) == 'integer')
assert(math.type(time.CLOCK_REALTIME) == 'integer')
assert(math.type(time.TFD_TIMER_ABSTIME) == 'integer')

local t0 = time.now()
assert(type(t0) == 'number' and t0 > 0, 'time.now() should return unix timestamp in seconds')

local os_now = os.time()
assert(math.abs(t0 - os_now) <= 1,
	   string.format('time.now() should be close to os.time(): now=%.3f os=%d', t0, os_now))

-- Argument validation.
test.expect_error(function()
	time.timer(1)
end, 'time.timer should reject non-function callback')

test.expect_error(function()
	time.at('0.01', function() end)
end, 'time.at should reject non-number delay')

test.expect_error(function()
	time.at(0.01, 1)
end, 'time.at should reject non-function callback')

test.expect_error(function()
	time.on('0', function() end)
end, 'time.on should reject non-number timestamp')

test.expect_error(function()
	time.on(time.now(), 1)
end, 'time.on should reject non-function callback')

-- Internal timerfd wrappers should return nil+error on invalid args.
do
	local fd, err = time.timerfd_create(-1)
	assert(fd == nil and type(err) == 'string', 'timerfd_create should fail with invalid clock id')
end

do
	local fd, err = time.timerfd_create(time.CLOCK_MONOTONIC)
	assert(fd, err)

	local ok
	ok, err = time.timerfd_settime(fd, 0, 0.01)
	assert(ok == true, err)

	assert(ifile.close(fd))
end

local sleep_elapsed
test.run_case_sync('sleep alias and now progression', function()
	eco.run(function()
		local start = time.now()
		time.sleep(0.02)
		sleep_elapsed = time.now() - start
	end)
end)

assert(sleep_elapsed and sleep_elapsed >= 0.01,
	   string.format('time.sleep should block for ~requested delay, got %.6f', sleep_elapsed or -1))

local timer_once_calls = 0
test.run_case_sync('timer set callback args', function()
	local tmr
	tmr = assert(time.timer(function(self, a, b)
		assert(self == tmr)
		assert(a == 'hello' and b == 7)
		timer_once_calls = timer_once_calls + 1
		self:close()
	end, 'hello', 7))

	local _, err = tmr:set(0.01)
	assert(err == nil, err)
end)

assert(timer_once_calls == 1, 'timer callback should run exactly once for one set()')

local at_repeat_calls = 0
test.run_case_sync('at re-arm from callback', function()
	assert(time.at(0.01, function(self)
		at_repeat_calls = at_repeat_calls + 1

		if at_repeat_calls < 3 then
			local _, err = self:set(0.01)
			assert(err == nil, err)
		else
			self:close()
		end
	end))
end)

assert(at_repeat_calls == 3, 'timer should re-arm and run callback multiple times')

local on_abs_fired = false
test.run_case_sync('on absolute timer', function()
	local tmr, err = time.on(time.now() + 0.02, function(self)
		on_abs_fired = true
		self:close()
	end)

	assert(tmr, err)
end)

assert(on_abs_fired, 'time.on absolute timer should fire')

local canceled_fired = false
test.run_case_sync('timer cancel', function()
	local tmr = assert(time.timer(function()
		canceled_fired = true
	end))

	local _, err = tmr:set(0.05)
	assert(err == nil, err)

	eco.run(function()
		eco.sleep(0.01)
		tmr:cancel()
		tmr:close()
	end)

	-- Keep loop alive long enough to prove callback stays canceled.
	eco.run(function()
		eco.sleep(0.08)
	end)
end)

assert(canceled_fired == false, 'timer callback should not run after cancel')

test.run_case_sync('timer set invalid delay', function()
	local tmr = assert(time.timer(function() end))

	local ok, err = tmr:set(-1)
	assert(ok == nil and type(err) == 'string', 'timer:set should fail on invalid negative delay')

	tmr:close()
end)

-- GC regression: timer should be collectible after completion.
do
	local weak = setmetatable({}, { __mode = 'v' })
	local fired = false

	eco.run(function()
		local tmr = assert(time.at(0.01, function(self)
			fired = true
			self:close()
		end))

		weak.tmr = tmr
	end)

	test.wait_until('timer gc callback fired', function()
		return fired
	end, 2.0)

	test.full_gc()
	assert(weak.tmr == nil, 'timer object should be collectible after callback completes')
end

-- Stress + leak regression: memory should plateau across equal timer bursts.
do
	test.full_gc()

	local function timer_burst(rounds, n, delay)
		local fired = 0

		for _ = 1, rounds do
			local timers = {}
			local round_target = fired + n

			for _ = 1, n do
				local tmr, err = time.at(delay, function(self)
					fired = fired + 1
					self:close()
				end)

				assert(tmr, err)
				timers[#timers + 1] = tmr
			end

			test.wait_until('timer burst round completes', function()
				return fired == round_target
			end, 5.0)

			for i = 1, #timers do
				timers[i] = nil
			end

			test.full_gc()
		end

		return fired
	end

	local rounds = 10
	local per_round = 1000
	local expected = rounds * per_round
	local base_mem_kb = test.lua_mem_kb()

	assert(timer_burst(rounds, per_round, 0.01) == expected)
	local after_first_kb = test.lua_mem_kb()

	assert(timer_burst(rounds, per_round, 0.01) == expected)
	local after_second_kb = test.lua_mem_kb()

	local growth_first_kb = after_first_kb - base_mem_kb
	local growth_second_kb = after_second_kb - after_first_kb
	local plateau_limit_kb = math.max(128, growth_first_kb * 0.30)

	assert(growth_first_kb < 8192,
		   string.format('unexpectedly large initial timer memory growth: %.2f KB', growth_first_kb))

	assert(growth_second_kb <= plateau_limit_kb,
		   string.format('timer memory keeps growing across equal bursts: first %.2f KB, second %.2f KB (limit %.2f KB)',
				 growth_first_kb, growth_second_kb, plateau_limit_kb))
end

-- Automatic GC regression: unreachable timers should be reclaimed and fd auto-closed.
do
	test.full_gc()

	local weak = setmetatable({}, { __mode = 'v' })
	local fds = {}
	local fired = 0
	local n = 128

	for i = 1, n do
		local tmr, err = time.at(0.01, function()
			fired = fired + 1
		end)
		assert(tmr, err)

		weak[i] = tmr
		fds[i] = tmr.tfd
	end

	test.wait_until('auto gc timers all fired', function()
		return fired == n
	end, 2.0)
	assert(fired == n, 'all auto-gc timer callbacks should fire')

	test.full_gc()

	for i = 1, n do
		assert(weak[i] == nil, 'timer should be collectible without explicit close when unreachable')

		local closed, cerr = ifile.close(fds[i])
		assert(closed == nil and type(cerr) == 'string',
			   'timer fd should be closed by __gc when timer object is unreachable')
	end
end

print('time tests passed')
