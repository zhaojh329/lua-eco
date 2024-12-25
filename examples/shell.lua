#!/usr/bin/env eco

local sys = require 'eco.sys'

local stdout, stderr, err = sys.sh('date', '-u')
print('stdout:', stdout)
print('stderr:', stderr)

if err then
    print('err:', err)
end

print('-----------------')

stdout, stderr, err = sys.sh('date -u >&2')
print('stdout:', stdout)
print('stderr:', stderr)

if err then
    print('err:', err)
end

print('-----------------')

stdout, stderr, err = sys.sh('sleep 2', 1)
print('stdout:', stdout)
print('stderr:', stderr)

if err then
    print('err:', err)
end
