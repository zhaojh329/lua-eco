-- SPDX-License-Identifier: MIT
-- Author: Jianhui Zhao <zhaojh329@gmail.com>

---
-- Logging utilities.
--
-- This module provides simple logging helpers backed by syslog/stdout/file.
--
-- - Default level: @{log.INFO}
-- - Default flags: @{log.FLAG_LF}
--
-- Output backend selection:
--
-- - If stdout is a TTY, logs go to stdout.
-- - Otherwise logs go to syslog.
-- - If @{set_path} is called with a non-empty path, logs are appended to that file.
--
-- Log levels (syslog priorities):
--
-- - @{log.EMERG}
-- - @{log.ALERT}
-- - @{log.CRIT}
-- - @{log.ERR}
-- - @{log.WARNING}
-- - @{log.NOTICE}
-- - @{log.INFO}
-- - @{log.DEBUG}
--
-- Flags:
--
-- - @{log.FLAG_LF} - append '\n'
-- - @{log.FLAG_FILE} - filename:line
-- - @{log.FLAG_PATH} - full path:line
--
-- Notes about message arguments:
--
-- - The logging functions accept varargs.
-- - Only `string`, `number`, `boolean` and `nil` values are rendered; other types are ignored.
--
-- @module eco.log

local log = require 'eco.internal.log'

local M = {
    --- Syslog priority: system is unusable.
    EMERG = log.EMERG,
    --- Syslog priority: action must be taken immediately.
    ALERT = log.ALERT,
    --- Syslog priority: critical conditions.
    CRIT = log.CRIT,
    --- Syslog priority: error conditions.
    ERR = log.ERR,
    --- Syslog priority: warning conditions.
    WARNING = log.WARNING,
    --- Syslog priority: normal but significant condition.
    NOTICE = log.NOTICE,
    --- Syslog priority: informational message.
    INFO = log.INFO,
    --- Syslog priority: debug-level message.
    DEBUG = log.DEBUG,

    --- Flag: append a trailing line feed (`'\n'`).
    FLAG_LF = log.FLAG_LF,
    --- Flag: include `filename:line` in the prefix.
    FLAG_FILE = log.FLAG_FILE,
    --- Flag: include full `path:line` in the prefix.
    FLAG_PATH = log.FLAG_PATH,
}

return setmetatable(M, { __index = log })
