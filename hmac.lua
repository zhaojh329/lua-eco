-- SPDX-License-Identifier: MIT
-- Author: Jianhui Zhao <zhaojh329@gmail.com>

--- HMAC utilities.
--
-- This module implements HMAC for the hash modules shipped with eco
-- (currently md5/sha1/sha256).
--
-- The returned digest is raw binary bytes. Use @{eco.encoding.hex.encode} if you
-- need a printable hexadecimal string.
--
-- @module eco.hash.hmac

local M = {}

local blocksize = 64

--- HMAC context returned by @{hmac.new}.
--
-- @type hmac
local methods = {}

--- Update HMAC with more data.
--
-- @function hmac:update
-- @tparam string data Chunk to add.
function methods:update(data)
    assert(type(data) == 'string', 'expecting data to be a string')

    self.ctx:update(data)
end

--- Finalize and return the HMAC digest.
--
-- @function hmac:final
-- @treturn string Raw binary digest.
function methods:final()
    return self.hash.sum(self.key .. self.ctx:final())
end

--- End of `hmac` class section.
-- @section end

local metatable = {
    __index = methods
}

--- Create a new HMAC context.
--
-- @function new
-- @tparam table hash Hash module (must be one of the eco hash modules (e.g. `eco.hash.sha256`)).
-- @tparam string key Secret key.
-- @treturn hmac HMAC context.
-- @usage
-- local sha256 = require 'eco.hash.sha256'
-- local hmac = require 'eco.hash.hmac'
-- local hex = require 'eco.encoding.hex'
--
-- local ctx = hmac.new(sha256, 'key')
-- ctx:update('12')
-- ctx:update('34')
-- print(hex.encode(ctx:final()))
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

--- One-shot HMAC.
--
-- @function sum
-- @tparam table hash Hash module (must be one of the eco hash modules (e.g. `eco.hash.sha256`)).
-- @tparam string key Secret key.
-- @tparam string data Data to authenticate.
-- @treturn string Raw binary digest.
function M.sum(hash, key, data)
    local ctx = M.new(hash, key)

    ctx:update(data)

    return ctx:final()
end

return M
