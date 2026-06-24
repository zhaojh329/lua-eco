# Usage Patterns

Use these patterns after selecting the capability family. Verify exact signatures in
`references/91-api-quick-reference.md` and exact symbol presence in
`references/90-public-api-manifest.md`.

## Program Shape
- Complete new programs: use `references/94-program-skeleton.md`.
- Small snippets or functions: keep the user's requested shape, but still use `eco` APIs and cleanup.
- Libraries: return functions or tables; do not call `main()` or start the scheduler.

## Generation Protocol
- For covered high-risk modules, consult `references/95-high-risk-api-shapes.md` before generating field access, tuple unpacking, or handler registration.
- Confirm symbol existence in `references/90-public-api-manifest.md` before generating calls.
- Use runnable examples/tests to validate object shapes before trusting generic intuition.
- Before answering, re-scan the draft for invented fields such as `resp.status_code` or fabricated callback APIs.

## Verification
- Syntax check Lua with `luac5.4 -p` after meaningful edits when validation is appropriate.
- If `luac5.4` is not installed, prefer `luac -p` only when its reported version is Lua 5.4.
- If neither is available, try to install the Lua 5.4 compiler package for the current system instead of failing immediately.
- If the install path needs approval for privilege or network access, request that approval and continue after it is granted.

## TCP and UDP
- TCP server: `socket.listen_tcp`, accept loop, `eco.run` per client, read/write with timeouts, close each client.
- TCP client: `socket.connect_tcp`, request/response reads with timeouts, close on all exits.
- UDP server/client: `socket.listen_udp` or `socket.connect_udp`, `recvfrom`/`sendto`, handle packet size and timeout.

## HTTP, WebSocket, MQTT
- HTTP client: prefer `eco.http.client.get/post/request`; use `local resp, err = ...`; validate status with `resp.code`; use `resp.status`, `resp.headers`, and optional `resp.body`.
- HTTP server: use `eco.http.server.listen`; handler receives `(con, req)`; read or discard request bodies.
- WebSocket: use `eco.websocket.connect` or `upgrade`; unpack frames as `data, typ, err`; handle `text`, `binary`, `ping`, `pong`, `close`, and fragmented frames.
- MQTT: use `eco.mqtt.new`; register handlers with `client:on`; follow repo example signatures such as `conack(ack, client)` and `publish(msg, client)`; drive reconnect behavior around `client:run()`.

## Files, Processes, Timers
- Files: use `eco.file.open/readfile/writefile/inotify`; close handles with explicit cleanup or Lua 5.4 `<close>`.
- Processes: prefer `eco.sys.exec` array/table forms when shell syntax is not required; use `local p, err = sys.exec(...)`, then `p:read_stdout`, `p:read_stderr`, and `p:wait`.
- Timers: use `eco.time.timer/at/on`; close timers when they are no longer needed.

## Platform Integrations
- UBus/UCI: use `eco.ubus` and `eco.uci`; do not shell out to `ubus` or edit config files by hand.
- Netlink/IP/nl80211: use `eco.nl`, `eco.genl`, `eco.rtnl`, `eco.ip`, `eco.nl80211`; validate message types and missing capabilities.
- SSH: use `eco.ssh`; handle connect/auth failure and free sessions.

## Encoding and Digests
- Use raw digest bytes from hash modules unless the user asks for hex/base64 output.
- Use `eco.encoding.hex` or `eco.encoding.base64` to present binary data.
