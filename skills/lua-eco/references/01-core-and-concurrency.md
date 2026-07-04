# Core and Concurrency

## Module eco
Public functions:
- eco.io
- eco.reader
- eco.writer
- eco.sleep
- eco.run
- eco.count
- eco.all
- eco.set_panic_hook
- eco.set_watchdog_timeout
- eco.loop
- eco.unloop

Constants:
- eco.VERSION
- eco.VERSION_MAJOR
- eco.VERSION_MINOR
- eco.VERSION_PATCH
- eco.READ
- eco.WRITE

Object methods:
- io:wait / io:cancel
- reader:wait / reader:read / reader:readfull / reader:readuntil / reader:cancel
- writer:wait / writer:write / writer:sendfile / writer:cancel

## Module eco.time
Common functions:
- time.sleep
- time.now
- time.timer
- time.at
- time.on

## Module eco.sync
- sync.cond
- sync.waitgroup
- sync.mutex

Object methods:
- cond:wait / cond:signal / cond:broadcast
- waitgroup:add / waitgroup:done / waitgroup:wait
- mutex:lock / mutex:unlock

## Module eco.channel
- channel.new
- channel:length
- channel:close
- channel:send
- channel:recv

## Generation Guidance
- Prefer eco.run for concurrent tasks.
- Prefer mutex or channel for shared state to avoid implicit races.
- Use timeouts and cancellation mechanisms for long-lived flows.
