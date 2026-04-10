#!/usr/bin/env eco

local log = require 'eco.log'

log.debug('eco')
log.info('eco')
log.err('eco')

log.set_ident(arg[0])

-- default is log.INFO
log.set_level(log.DEBUG)

-- default is log.FLAG_LF
-- log.FLAG_LF: append a character '\n' to every log message
-- log.FLAG_FILE: filename and line number
-- log.FLAG_PATH: full file path and line number
log.set_flags(log.FLAG_LF | log.FLAG_PATH)

log.debug(1, 2, 3)
log.info('eco')
log.err('eco', eco.VERSION)

log.log(log.WARNING, 'eco')

log.set_path('/tmp/eco.log')

-- Rotate when log file reaches 1MB.
-- Set to 0 to disable rolling.
log.set_roll_size(1024 * 1024)

-- Keep at most 5 rolled files.
log.set_roll_count(5)

log.info('eco')
