# Platform Integration and Devices

## Module eco.ubus
Top-level functions:
- call
- send
- objects
- signatures
- connect

connection methods:
- close
- call
- send
- reply
- listen
- add
- subscribe
- unsubscribe
- notify
- objects
- signatures

## Module eco.uci
Top-level functions:
- cursor

cursor methods:
- close
- load
- unload
- get
- get_all
- add
- set
- rename
- save
- delete
- commit
- revert
- reorder
- foreach
- each
- get_confdir
- set_confdir
- get_savedir
- set_savedir
- list_configs

## Module eco.shared
Top-level functions:
- new
- get

dict methods:
- del
- set
- get
- incr
- ttl
- expire
- flush_all
- get_keys
- close

## Module eco.log
- set_level
- debug
- info
- err
- log
- set_path
- set_flags
- set_roll_size
- set_roll_count
- set_ident
- Log methods accept varargs and join supported values with spaces.
- Do not use printf-style placeholders directly in `log.debug/info/err/log`; use `string.format(...)` first when needed.

## Module eco.termios
Top-level functions:
- tcgetattr
- tcsetattr
- tcflush
- tcflow

attr methods:
- set_flag
- clr_flag
- set_cc
- get_ispeed
- get_ospeed
- set_ispeed
- set_ospeed
- set_speed
- clone

## Module eco.ssh
- new

session methods:
- exec
- scp_recv
- scp_send
- scp_sendfile
- disconnect
- free

## Review Focus
- Platform dependencies must be declared explicitly.
- Device and configuration operations should include rollback or failure recovery.
- Remote execution and transfer flows must fully handle exit codes and errors.
