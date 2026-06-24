# Regression Prompts

Purpose: quickly stress-test this skill for code generation, code review, and routing-guard stability.

Usage:
1. Send each prompt to the model exactly as written unless intentionally testing skill activation.
2. Compare the output against the expected capability and API family.
3. Check whether common misroutes trigger fallback rewrites.

Prompt scope:
- Code-generation cases are lua-eco regressions. The expected language/runtime is Lua 5.4 running on `eco`, using public lua-eco APIs.
- If a code-generation answer uses Python, Node.js, Go, Rust, curl/wget, or shell commands as the main implementation, mark it as a fail before evaluating API-family details.
- Prompts should put lua-eco near the beginning, preferably in a natural "Use lua-eco to write ..." form, unless the case explicitly tests activation from an ambiguous prompt.

## A. Code Generation

### Case A1: TCP Echo Server
- Prompt: Use lua-eco to write a TCP echo server that listens on 0.0.0.0:9000, supports concurrent clients, and disconnects clients after 10 seconds of inactivity.
- Expected capability/API family: program skeleton, eco.socket listen_tcp/accept/read/write, eco.run, timeout handling.
- Common misroute: using http.server instead of raw TCP; missing timeout, close, or program skeleton.

### Case A2: HTTP File Download Client
- Prompt: Use lua-eco to write an HTTPS file download client with request timeout and status-code validation.
- Expected capability/API family: program skeleton, eco.http.client.get/request with `opts.timeout` and file output handling, status-code validation, and eco.ssl TLS options when needed.
- Common misroute: using Python requests, curl/wget, Node fetch, or shell commands as the main implementation; hand-writing HTTP over raw sockets; ignoring status code or timeout; using printf-style logging like `log.err('download failed: %s', err)`; checking `resp.status_code` instead of `resp.code`.

### Case A3: WebSocket Client Heartbeat
- Prompt: Use lua-eco to write a WebSocket client that sends ping every 20 seconds after connecting and prints incoming text messages.
- Expected capability/API family: eco.websocket.connect, send_ping, recv_frame.
- Common misroute: treating WebSocket as a long HTTP connection; missing ping/pong handling; fabricating callback-style `on_message` APIs or treating `recv_frame()` as a message object instead of `data, typ, err`.

### Case A4: MQTT Publish and Subscribe
- Prompt: Use lua-eco to write an MQTT client that subscribes to test/#, publishes to test/hello every second, and reconnects automatically after disconnects.
- Expected capability/API family: eco.mqtt.
- Common misroute: assembling MQTT packets directly over TCP; no reconnect strategy; inventing foreign client APIs such as `connect()`, `loop_forever()`, or `on_message`.

### Case A5: DNS Resolver Tool
- Prompt: Use lua-eco to write a small tool that accepts a domain name and returns A and AAAA records, printing readable errors on failure.
- Expected capability/API family: eco.dns.query.
- Common misroute: using shell commands such as dig or nslookup as the main path.

### Case A6: File Change Watcher
- Prompt: Use lua-eco to write a file change watcher for create and delete events under /tmp/demo, printing file names.
- Expected capability/API family: eco.file.inotify.
- Common misroute: polling with sleep plus directory scans.

### Case A7: Process Execution and Output Collection
- Prompt: Use lua-eco to write a process execution tool that runs ip addr, collects stdout, stderr, and exit code, and applies a 5-second timeout.
- Expected capability/API family: eco.sys.exec/sh plus process.wait/read_stdout/read_stderr.
- Common misroute: using os.execute or io.popen as the main path; assuming `sys.exec()` directly returns stdout/stderr or a bare numeric exit code.

### Case A8: Shared Counter
- Prompt: Use lua-eco to write a shared-memory cross-process counter that supports incr and ttl.
- Expected capability/API family: eco.shared.
- Common misroute: using only a Lua global variable for cross-process sharing.

### Case A9: Configuration Read and Write
- Prompt: Use lua-eco to write a UCI configuration tool that reads and modifies network.lan.ipaddr, then commits the change.
- Expected capability/API family: eco.uci.
- Common misroute: editing configuration files directly through shell commands.

### Case A10: Tunnel Interface Creation
- Prompt: Use lua-eco to write a tun or tap device example that sends and receives data through it and cleans up resources.
- Expected capability/API family: eco.socket.open_tun.
- Common misroute: treating AF_PACKET raw sockets as tunnel device creation.

### Case A11: Link-Layer Packet Capture
- Prompt: Use lua-eco to write a link-layer packet capture tool that captures ARP and IPv4 packets on a specified interface and parses key fields.
- Expected capability/API family: eco.socket packet-related capabilities plus eco.packet.
- Common misroute: treating open_tun as a link-layer capture interface.

### Case A12: Batch SSH Execution
- Prompt: Use lua-eco to write a batch SSH execution tool that runs commands on three hosts and summarizes stdout plus exit code.
- Expected capability/API family: eco.ssh.
- Common misroute: calling the shell ssh command as the only implementation path.

### Case A13: Netlink Address Management
- Prompt: Use lua-eco to write a netlink address management tool that adds and deletes an IPv4 address on eth0, then lists current addresses.
- Expected capability/API family: eco.ip.address.
- Common misroute: using only the shell ip command instead of netlink APIs.

### Case A14: Wireless Scan
- Prompt: Use lua-eco to write a wireless scan tool that triggers a Wi-Fi scan and prints SSID, BSSID, and signal strength.
- Expected capability/API family: eco.nl80211.scan.
- Common misroute: missing nl80211 capability checks; parsing fields incorrectly.

### Case A15: Minimal Snippet Exception
- Prompt: Use lua-eco to write only the handler function for one accepted TCP client; do not include a full program.
- Expected capability/API family: no program skeleton, eco.socket client read/write methods, timeout handling.
- Common misroute: wrapping the snippet in the full guide.lua-style skeleton despite the user's constraint.

### Case A16: From-Zero Program Skeleton
- Prompt: Use lua-eco to write a complete tool that polls https://example.com every 30 seconds and logs non-200 responses.
- Expected capability/API family: program skeleton, eco.http.client.get, eco.run or loop inside main, timeout and cleanup.
- Common misroute: emitting a fragment, leaving `eco-demo` as log ident, or calling eco.loop manually.

### Case A17: Missing luac5.4 Verifier
- Prompt: Use lua-eco to write a small script, then verify its syntax. The host does not have `luac5.4` installed.
- Expected capability/API family: use `luac5.4 -p`; if missing, check whether plain `luac` is Lua 5.4; otherwise attempt package-manager installation and request approval when network or elevated permissions are required.
- Common misroute: failing immediately on "command not found"; silently skipping verification; using a non-5.4 `luac` binary without checking the version.

### Case A18: HTTP Response Shape
- Prompt: Use lua-eco to write an HTTP GET tool that prints the status code, status text, and body for a URL.
- Expected capability/API family: `eco.http.client.get`; success path uses `resp.code`, `resp.status`, `resp.headers`, and optional `resp.body`.
- Common misroute: using `res.status_code`, `resp.statusCode`, `resp.ok`, `response.text()`, or other non-lua-eco fields.

### Case A19: WebSocket Return Tuple
- Prompt: Use lua-eco to connect to a WebSocket server, send one text frame, then print the returned frame type and payload.
- Expected capability/API family: `eco.websocket.connect`, `send_text`, `recv_frame`; receive path unpacks `data, typ, err`.
- Common misroute: treating the receive result as a single table/object with `type` and `data` fields; inventing callback-only handlers.

### Case A20: Process Handle Semantics
- Prompt: Use lua-eco to run `/bin/sh -c 'printf out; printf err 1>&2; exit 7'`, then print stdout, stderr, and exit status.
- Expected capability/API family: `sys.exec` returning `p, err`; `p:read_stdout`, `p:read_stderr`, `p:wait`.
- Common misroute: assuming `sys.exec()` returns combined output directly; treating `status` as a bare number rather than a table.

### Case A21: MQTT Handler Shapes
- Prompt: Use lua-eco to connect to MQTT, subscribe to one topic, print published messages, and log connection errors.
- Expected capability/API family: `mqtt.new`, `client:on`, `client:run`; handler shapes must follow repo examples such as `publish(msg, client)` and `error(err)`.
- Common misroute: inventing event names like `message`, `connect`, or `disconnect` without evidence; using foreign callback payload shapes.

## B. Code Review

### Case B1: Blocking Misuse Review
- Prompt: Review this lua-eco code for blocking calls and scheduler risks. List issues by severity.
- Expected capability/API family: review template plus scheduler-safety rules.
- Common misroute: modifying the code immediately instead of listing findings first.

### Case B2: API Mismatch Review
- Prompt: Review this lua-eco tunnel-device implementation, focusing on whether API selection is correct.
- Expected capability/API family: capability matrix, anti-pattern constraints, symbol gate.
- Common misroute: giving style feedback without identifying capability mismatch.

### Case B3: Resource Leak Review
- Prompt: Review this lua-eco code for socket, file, process, or timer leaks, and give the smallest fix.
- Expected capability/API family: resource lifecycle review dimensions.
- Common misroute: discussing only the happy path.

### Case B4: Test Gap Review
- Prompt: Review which tests are missing from this lua-eco network code, ordered by risk.
- Expected capability/API family: test-gap dimension from the review template.
- Common misroute: saying "add tests" without concrete scenarios.

## C. Acceptance Criteria

Pass:
1. Output APIs match capabilities and avoid cross-capability mismatches.
2. No nonexistent function names are called.
3. Covered high-risk modules use the documented field names, return tuples, and handler signatures.
4. Generated code includes timeout, error handling, and cleanup.
5. From-zero complete programs use the program skeleton unless the user asks for a snippet/module/test.
6. Review output is finding-first and ordered by severity.

Fail:
1. Replacing the correct capability path with a merely similar API.
2. Hallucinated functions or wrong module names.
3. Inventing undocumented fields, return tuples, or handler signatures such as `resp.status_code`.
4. Ignoring resource cleanup and error paths.
5. Calling eco.internal modules from user code.
6. Calling eco.loop in normal entry scripts.
7. Using another programming language or shell-only implementation for code-generation cases that expect lua-eco.
