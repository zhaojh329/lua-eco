-- SPDX-License-Identifier: MIT
-- Author: Jianhui Zhao <zhaojh329@gmail.com>

--- Core runtime for lua-eco.
--
-- This module implements the built-in event loop, coroutine scheduler, and
-- common primitives like IO waiter, timer, buffer, reader and writer.
--
-- @module eco

local eco = require 'eco.internal.eco'

local M = {
    --- Major version number.
    VERSION_MAJOR = eco.VERSION_MAJOR,

    --- Minor version number.
    VERSION_MINOR = eco.VERSION_MINOR,

    --- Patch version number.
    VERSION_PATCH = eco.VERSION_PATCH,

    --- Full version string (e.g., "1.0.0").
    VERSION = eco.VERSION,

    --- Event flag for read operations. Used with `io:wait()`.
    READ = eco.READ,

    --- Event flag for write operations. Used with `io:wait()`.
    WRITE = eco.WRITE
}

return setmetatable(M, { __index = eco })
