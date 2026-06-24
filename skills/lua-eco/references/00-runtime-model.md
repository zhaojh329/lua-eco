# Runtime Model

Read this before generating complete lua-eco programs or reviewing scheduler behavior.

## Interpreter and Entry Script
- Run programs with the `eco` interpreter, usually via `#!/usr/bin/env eco`.
- The `eco` module is built into the interpreter and injected into `_G.eco`.
- `local eco = require 'eco'` is still acceptable and helps linters.
- The entry script already runs inside a coroutine created by the interpreter.
- The interpreter starts the scheduler internally. Do not call `eco.loop()` in ordinary scripts.

## Scheduler Model
- lua-eco exposes synchronous-looking Lua APIs backed by non-blocking file descriptors.
- When an operation would block, the current coroutine yields.
- The scheduler waits on epoll/timers and resumes the coroutine when the operation can continue.
- Code should stay cooperative: avoid long CPU loops and blocking libraries on scheduler paths.

## Concurrency Model
- Use `eco.run(fn, ...)` to start additional coroutines.
- Use `eco.channel`, `eco.sync.mutex`, `eco.sync.cond`, or `eco.sync.waitgroup` for coordination.
- Add timeouts to external I/O and long waits unless the user explicitly wants an indefinite wait.
- Treat `nil, err` as the normal failure convention for eco APIs.

## Lifecycle Rules
- Close sockets, files, timers, HTTP/WebSocket/MQTT/SSH contexts, and signal handles.
- Wait on or close process handles to avoid leaks.
- Cleanup should be idempotent and should run on error paths.
