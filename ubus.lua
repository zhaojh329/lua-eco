--[[
 * MIT License
 *
 * Copyright (c) 2022 Jianhui Zhao <zhaojh329@gmail.com>
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
--]]

local ubus = require 'eco.core.ubus'

local M = {}

-- low level ubus condition
local connections = setmetatable({}, { __mode = 'v' })

-- high level condition
local connections_cache = {}

local function process_msg(con, w, done)
    while not done.v do
        if not w:wait() then
            return
        end
        con:process_msg()
    end
end

local methods = {}

function methods:closed()
    local mt = getmetatable(self)
    return mt.done.v
end

function methods:close()
    local mt = getmetatable(self)
    local done = mt.done
    local con = mt.con

    if done.v then
        return
    end

    done.v = true
    mt.w:cancel()
    con:close()
    connections[con] = nil
    connections_cache[self] = nil
end

function methods:call(object, method, params)
    local mt = getmetatable(self)

    if mt.done.v then
        return nil, 'closed'
    end

    local req, err = mt.con:call(object, method, params)
    if not req then
        return nil, err
    end

    local res, err

    if eco.watcher(eco.IO, req:wait_fd()):wait(30) then
        res = req:parse()
    else
        err = 'timeout'
    end

    req:close()

    return res, err
end

function methods:reply(req, msg)
    local mt = getmetatable(self)

    if mt.done.v then
        return nil, 'closed'
    end

    return mt.con:reply(req, msg)
end

function methods:add(object, methods)
    local mt = getmetatable(self)

    if mt.done.v then
        return nil, 'closed'
    end

    local __methods = {}

    for name, method in pairs(methods) do
        if type(method) == 'table' and #method > 0 and type(method[1]) == 'function' then
            __methods[name] = {
                function(con, req, msg)
                    con = connections[con]
                    if con then
                        method[1](con, req, msg)
                    end
                end,
                method[2]
            }
        end
    end

    local o, err = mt.con:add(object, __methods)
    if not o then
        return false, err
    end

    if not connections_cache[self] then
        connections_cache[self] = true
    end

    return true
end

function methods:listen(event, cb)
    local mt = getmetatable(self)

    if mt.done.v then
        return nil, 'closed'
    end

    local e, err = mt.con:listen(event, function(con, ev, msg)
        con = connections[con]
        if con then
            cb(con, ev, msg)
        end
    end)
    if not e then
        return false, err
    end

    if not connections_cache[self] then
        connections_cache[self] = true
    end

    return true
end

function methods:send(event, msg)
    local mt = getmetatable(self)

    if mt.done.v then
        return nil, 'closed'
    end

    return mt.con:send(event, msg)
end

function M.connect(path)
    local __con, err = ubus.connect(eco.context(), path)

    if not __con then
        return nil, err
    end

    local con = {}

    connections[__con] = con

    local w = eco.watcher(eco.IO, __con:getfd())
    local done = { v = false }

    eco.run(process_msg, __con, w, done)

    if tonumber(_VERSION:match('%d%.%d')) < 5.2 then
        local __prox = newproxy(true)
        getmetatable(__prox).__gc = function() methods.close(con) end
        con[__prox] = true
    end

    return setmetatable(con, {
        w = w,
        done = done,
        con = __con,
        __index = methods,
        __gc = function() methods.close(con) end
    })
end

function M.call(object, method, params)
    local con, err = M.connect()
    if not con then
        return nil, err
    end

    local res, err = con:call(object, method, params)
    con:close()
    return res, err
end

function M.send(event, params)
    local con, err = ubus.connect(eco.context())
    if not con then
        return nil, err
    end

    con:send(event, params)
    con:close()

    return true
end

return M
