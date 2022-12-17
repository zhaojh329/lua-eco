#!/usr/bin/env eco

local log = require 'eco.log'

log.debug('eco')
log.info('eco')
log.err('eco')

-- default is log.INFO
log.level(log.DEBUG)

log.debug('eco')
log.info('eco')
log.err('eco')

log.log(log.LOG_WARNING, 'eco')

log.set_path('/tmp/eco.log')

log.info('eco')
