#!/usr/bin/env eco

local sys = require 'eco.sys'

local p<close>, err = sys.exec('cat')
if not p then
    error(err)
end

-- For large inputs, read output concurrently or use sys.sh below.
assert(p:write_stdin('hello ', 1))
assert(p:write_stdin('world\n', 1))
p:close_stdin()

local stdout = assert(p:read_stdout('*a', 1))
local pid, status = p:wait(1)
assert(pid, status)
assert(status.exited and status.status == 0)
assert(stdout == 'hello world\n')
io.write('exec stdout: ', stdout)

local stderr
stdout, stderr, err = sys.sh('cat', 1, 'hello from sh\n')
assert(stdout, err)
assert(stdout == 'hello from sh\n' and stderr == '')
io.write('sh stdout: ', stdout)
