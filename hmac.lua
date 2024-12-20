-- SPDX-License-Identifier: MIT
-- Author: Jianhui Zhao <zhaojh329@gmail.com>

local M = {}

local blocksize = 64

local methods = {}

function methods:update(data)
    assert(type(data) == 'string', 'expecting data to be a string')

    self.ctx:update(data)
end

function methods:final()
    return self.hash.sum(self.key .. self.ctx:final())
end

local metatable = {
    __index = methods
}

function M.new(hash, key)
    local mtname = hash and hash.mtname

    assert(mtname == 'eco{md5}'
        or mtname == 'eco{sha1}'
        or mtname == 'eco{sha256}',
        'expecting hash to be a hash module')

    assert(type(key) == 'string', 'expecting key to be a string')

    if #key > blocksize then
        key = hash.sum(key)
    end

    local key_xord_with_0x36 = key:gsub('.', function(c)
        return string.char(c:byte() ~ 0x36)
    end) .. string.rep(string.char(0x36), blocksize - #key)

    local key_xord_with_0x5c = key:gsub('.', function(c)
        return string.char(c:byte() ~ 0x5c)
    end) .. string.rep(string.char(0x5c), blocksize - #key)

    local ctx = hash.new()

    ctx:update(key_xord_with_0x36)

    return setmetatable({
        ctx = ctx,
        hash = hash,
        key = key_xord_with_0x5c
    }, metatable)
end

function M.sum(hash, key, data)
    local ctx = M.new(hash, key)

    ctx:update(data)

    return ctx:final()
end

return M
