# Files, Processes, and System IO

## Module eco.file
Top-level capabilities:
- readfile / writefile / open / inotify / walk
- Public wrappers such as stat, fstat, statvfs, dir, dirname, basename, and readlink

file object methods:
- read / readfull / readuntil / write / lseek / stat / flock / close

inotify object methods:
- wait / add / del / close

## Module eco.sys
process object methods:
- close / wait / signal / kill / stop / read_stdout / read_stderr

Top-level functions:
- exec
- sh
- spawn
- signal

signal_handle methods:
- close

## Generation Guidance
- Prefer the array-argument form of sys.sh when shell syntax is not required.
- `sys.exec(...)` returns `process, err`; it does not return stdout, stderr, or exit status directly.
- `process:wait(timeout)` returns `pid, status` on success; `status` is a table, not a bare numeric exit code.
- `sys.sh(cmd[, timeout])` returns `stdout, stderr` on success; failures report the error string in the third return value.
- Process objects must be waited on or closed to avoid zombie processes and handle leaks.
- File read/write error branches must be handled and resources must be cleaned up.

## Review Focus
- Missing timeouts.
- Missing close or wait calls.
- Shell-string invocation where array execution would be sufficient.
