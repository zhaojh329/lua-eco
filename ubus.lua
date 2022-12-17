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

local connections = setmetatable({}, { __mode = 'v' })

local function process_msg(con, w, done)
    while not done.v do
        if not w:wait() then
            return
        end
        con:process_msg()
    end
end

local mt = {}

function mt:closed()
    return self.__done.v
end

function mt:close()
    if self:closed() then
        return
    end
    self.__done.v = true
    self.__con_w:cancel()
    self.__con:close()
    connections[self.__con] = nil
end

function mt:call(object, method, params)
    if self:closed() then
        return nil, 'closed'
    end

    local req, err = self.__con:call(object, method, params)
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

function mt:reply(req, msg)
    if self:closed() then
        return nil, 'closed'
    end

    return self.__con:reply(req, msg)
end

function mt:add(object, methods)
    if self:closed() then
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

    local o, err = self.__con:add(object, __methods)
    if not o then
        return false, err
    end

    return true
end

function mt:listen(event, cb)
    if self:closed() then
        return nil, 'closed'
    end

    local e, err = self.__con:listen(event, function(con, ev, msg)
        con = connections[con]
        if con then
            cb(con, ev, msg)
        end
    end)
    if not e then
        return false, err
    end

    return true
end

function mt:send(event, msg)
    if self:closed() then
        return nil, 'closed'
    end

    return self.__con:send(event, msg)
end

function M.connect(path)
    local __con, err = ubus.connect(eco.context(), path)

    if not __con then
        return nil, err
    end

    local con = {
        __con = __con,
        __done = { v = false }
    }

    connections[__con] = con

    con.__con_w = eco.watcher(eco.IO, __con:getfd())
    eco.run(process_msg, __con, con.__con_w, con.__done)

    if tonumber(_VERSION:match('%d%.%d')) < 5.2 then
        local __prox = newproxy(true)
        getmetatable(__prox).__gc = function() mt.close(con) end
        con[__prox] = true
    end

    return setmetatable(con, {
        __index = mt,
        __gc = function() mt.close(con) end
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

return setmetatable(M, { __index = ubus })
