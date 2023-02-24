#!/usr/bin/env eco

local log = require 'eco.log'

log.debug('eco')
log.info('eco')
log.err('eco')

-- default is log.INFO
log.set_level(log.DEBUG)

log.debug(1, 2, 3)
log.info('eco')
log.err('eco', eco.VERSION)

log.log(log.LOG_WARNING, 'eco')

log.set_path('/tmp/eco.log')

log.info('eco')
