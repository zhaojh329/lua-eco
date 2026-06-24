# Common Mistakes

Check generated code and reviews against this list.

## Runtime and Scheduler
- Running eco programs with plain `lua` instead of `eco`.
- Calling `eco.loop()` from normal entry scripts.
- Using blocking libraries or shell commands on the main coroutine path when eco APIs exist.
- Starting long CPU loops without yielding or splitting work.
- Failing immediately when `luac5.4` is missing instead of checking for `luac` on Lua 5.4 or attempting package installation.
- Using a non-5.4 `luac` binary for validation without checking its version.

## API Selection
- Using raw sockets for HTTP/WebSocket/MQTT unless the user explicitly requests protocol implementation.
- Using HTTP APIs for plain TCP protocols.
- Using AF_PACKET/raw sockets as a replacement for `socket.open_tun`.
- Using shell commands as the primary implementation for UBus, UCI, netlink, or IP address management.
- Calling `eco.internal.*` modules from user code.
- Using printf-style placeholders directly in `eco.log`, such as `log.err('download failed: %s', err)`, instead of `log.err(string.format(...))` or `log.err('download failed:', err)`.

## Object Shapes and Return Conventions
- Using `resp.status_code`, `resp.statusCode`, `resp.ok`, or `response.text()` with `eco.http.client` instead of `resp.code`, `resp.status`, `resp.headers`, and optional `resp.body`.
- Treating `websocket.recv_frame()` as a single message object instead of unpacking `data, typ, err`.
- Assuming `sys.exec()` directly returns stdout/stderr or a bare numeric exit code instead of a process handle.
- Inventing MQTT event names or payload shapes from other client libraries instead of using lua-eco examples and documented handler signatures.

## Reliability
- Missing `nil, err` checks after I/O, process, DNS, TLS, HTTP, or platform calls.
- Missing timeout on external reads, writes, connects, accepts, waits, or command execution.
- Missing close/free/wait on sockets, files, timers, processes, signal handles, WebSocket, MQTT, HTTP, or SSH objects.
- Ignoring partial protocol state, such as HTTP request bodies, WebSocket ping/pong/close, MQTT reconnect/QoS, or netlink dump termination.

## Generated Program Quality
- Emitting only a fragment when the user asked for a complete runnable program.
- Omitting logging and panic hook setup in from-zero complete programs.
- Leaving `eco-demo` as the log ident instead of deriving a task-specific ident.
