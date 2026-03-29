#!/usr/bin/env eco

local eco = require 'eco'
local time = require 'eco.time'

local M = {}

function M.expect_error(fn, msg)
    local ok = pcall(fn)
    assert(not ok, msg)
end

function M.expect_error_contains(fn, needle, msg)
    local ok, err = pcall(fn)

    assert(not ok, msg)
    assert(type(err) == 'string' and err:find(needle, 1, true),
           string.format('expected error containing %q, got %q', needle, tostring(err)))
end

function M.full_gc()
    collectgarbage('collect')
    collectgarbage('collect')
end

function M.lua_mem_kb()
    M.full_gc()
    return collectgarbage('count')
end

function M.wait_until(name, predicate, timeout, interval)
    timeout = timeout or 5.0
    interval = interval or 0.001

    local deadline = time.now() + timeout

    while not predicate() do
        assert(time.now() < deadline,
               string.format('%s: timeout after %.3fs', name, timeout))
        eco.sleep(interval)
    end
end

function M.run_case_sync(name, fn)
    local base_count = eco.count()

    local ok, err = pcall(fn)
    assert(ok, name .. ': ' .. tostring(err))

    M.wait_until(name .. ' background drain', function()
        return eco.count() <= base_count
    end)
end

function M.run_case_async(name, fn)
    local base_count = eco.count()
    local done = false
    local case_err

    eco.run(function()
        local ok, err = pcall(fn)
        if not ok then
            case_err = err
        end

        done = true
    end)

    M.wait_until(name, function()
        return done and eco.count() <= base_count
    end)

    assert(case_err == nil, name .. ': ' .. tostring(case_err))
end

return M
