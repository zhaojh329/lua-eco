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

local file = require 'eco.core.file'
local sys = require 'eco.core.sys'

local M = {}

local exec_mt = {}

function exec_mt:release()
    if not self.__stdout then
        return
    end

    file.close(self.__stdout)
    file.close(self.__stderr)

    self.__stdout = nil
    self.__stderr = nil
end

function exec_mt:wait(timeout)
    return self.__child_w:wait(timeout or 30.0)
end

function exec_mt:read_stdout(n, timeout)
    if not self.__stdout_w:wait(timeout or 30.0) then
        return nil, 'timeout'
    end

    return file.read(self.__stdout, n)
end

function exec_mt:read_stderr(n, timeout)
    if not self.__stderr_w:wait(timeout or 30.0) then
        return nil, 'timeout'
    end

    return file.read(self.__stderr, n)
end

function M.exec(...)
    local pid, stdout, stderr = sys.exec(...)
    if not pid then
        return nil, stdout
    end

    local p = {
        pid = pid,
        __stdout = stdout,
        __stderr = stderr,
        __child_w = eco.watcher(eco.CHILD, pid),
        __stdout_w = eco.watcher(eco.IO, stdout),
        __stderr_w = eco.watcher(eco.IO, stderr),

    }

    if tonumber(_VERSION:match('%d%.%d')) < 5.2 then
        local __prox = newproxy(true)
        getmetatable(__prox).__gc = function() p:release() end
        p[__prox] = true
    end

    return setmetatable(p, {
        __index = exec_mt,
        __gc = function() p:release() end
    })
end

function M.signal(sig, cb, ...)
    eco.run(function(...)
        local w = eco.watcher(eco.SIGNAL, sig)
        while true do
            w:wait()
            cb(...)
        end
    end, ...)
end

return setmetatable(M, { __index = sys })
