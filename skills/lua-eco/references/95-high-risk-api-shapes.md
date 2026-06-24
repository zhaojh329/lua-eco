# High-Risk API Shapes and Return Conventions

Use this file as a hard constraint before generating code for covered modules.

## Rules
- Treat listed field names, return tuples, and handler signatures as authoritative for the covered modules.
- Do not infer shapes from Python requests, Fetch, Node.js streams, Go net/http, or other ecosystems.
- If a needed field or tuple is not listed here, inspect runnable examples/tests before generating it.
- If evidence is still incomplete, answer conservatively instead of inventing fields or behaviors.

## eco.http.client

Primary evidence:
- `examples/http/get.lua`
- `examples/http/post.lua`
- `examples/http/download_file.lua`
- `tests/http-test.lua`

Request helpers:
- `local resp, err = http.get(url[, opts])`
- `local resp, err = http.post(url[, body[, opts]])`
- `local resp, err = http.request(method, url[, body[, opts]])`

Success response object:
- `resp.code` - numeric HTTP status code
- `resp.status` - HTTP status text
- `resp.headers` - response headers table
- `resp.body` - response body string when kept in memory

Response handling rules:
- Always branch on `if not resp then ... end` for request failures.
- Validate status using `resp.code`.
- Print or inspect status text using `resp.status`.
- Use `resp.body` only when the body is not redirected to file output.
- When `opts.body_to_file` is used, body data is written to the target path and `resp.body` may be absent.

Reject these invented shapes:
- `resp.status_code`
- `resp.statusCode`
- `resp.ok`
- `response.text()`
- `response.json()`
- `res.status`

## eco.http.server

Primary evidence:
- `skills/lua-eco/references/91-api-quick-reference.md`
- `http/server.lua`

Handler shape:
- `http.listen(..., handler)` calls `handler(con, req)`

Common request table fields:
- `req.method`
- `req.raw_path`
- `req.path`
- `req.headers`
- `req.query`
- `req.query_string`
- `req.form`

Response behavior:
- Use connection methods such as `con:set_status`, `con:add_header`, `con:send_error`, `con:discard_body`, and `con:serve_file`.
- Do not invent a separate response object API.

Reject these invented shapes:
- Express-style `req.params` or `res.status(...)`
- Fetch-style `request.json()` / `response.sendStatus(...)`

## eco.websocket

Primary evidence:
- `examples/websocket/client.lua`
- `examples/websocket/server.lua`
- `tests/websocket-test.lua`
- `tests/websocket-frame-test.lua`

Connection helpers:
- `local ws, err = websocket.connect(uri[, opts])`
- `local ws, err = websocket.upgrade(con, req[, opts])`

Receive convention:
- Success: `local data, typ, err = ws:recv_frame([timeout])`
- Failure: `data == nil`, `typ == nil`, `err` carries the failure reason
- `typ` is one of `text`, `binary`, `continuation`, `close`, `ping`, `pong`
- For `typ == 'close'`, `data` is the close reason string and `err` may carry the close status code
- For fragmented messages, `err == 'again'` means more frames are required

Send convention:
- `local bytes, err = ws:send_text([data])`
- `local bytes, err = ws:send_binary([data])`
- `local bytes, err = ws:send_ping([data])`
- `local bytes, err = ws:send_pong([data])`
- `local bytes, err = ws:send_close([code[, msg]])`

Reject these invented shapes:
- `local msg = ws:recv_frame() ; print(msg.type, msg.data)`
- Callback-only handlers such as `ws:on_message(...)` without evidence
- Treating frame type as a field on `data`

## eco.mqtt

Primary evidence:
- `examples/mqtt.lua`
- `tests/mqtt-test.lua`

Client creation and run loop:
- `local client = mqtt.new([opts])`
- `client:run()` handles the network loop until disconnect or error
- Reconnect behavior belongs in caller-controlled loops around `client:run()`

Supported handler registration forms:
- `client:on(event, handler)`
- `client:on({ event1 = handler1, event2 = handler2 })`

Example handler signatures:
- `conack(ack, client)`
- `suback(ack)`
- `unsuback(topic)`
- `publish(msg, client)`
- `error(err)`

Observed payload fields from examples/tests:
- `ack.rc`
- `ack.reason`
- `ack.session_present`
- `ack.results`
- `msg.topic`
- `msg.payload`

Reject these invented shapes:
- `client:connect()`
- `client:loop_forever()`
- `client:on_message(...)`
- Event payloads copied from foreign MQTT libraries without repo evidence

## eco.sys

Primary evidence:
- `examples/exec/exec.lua`
- `examples/exec/env.lua`
- `tests/sys-test.lua`

Process execution:
- `local p, err = sys.exec(cmd, arg1, arg2, ...)`
- `local p, err = sys.exec({ cmd, arg1, arg2, ... }, env)`

Process handle behavior:
- `local stdout, err = p:read_stdout(format[, timeout])`
- `local stderr, err = p:read_stderr(format[, timeout])`
- `local pid, status = p:wait([timeout])`
- `status` is a table; observed fields include `exited`, `signaled`, and `status`
- `p:close()` closes the process I/O handles

Shell wrapper:
- `local stdout, stderr, err = sys.sh(cmd[, timeout])`

Reject these invented shapes:
- `local stdout, stderr, code = sys.exec(...)`
- `p.stdout` / `p.stderr` fields without evidence
- Treating `p:wait()` as returning only a numeric exit code

## eco.log

Primary evidence:
- `examples/log.lua`
- `tests/log-test.lua`

Logging behavior:
- `log.debug/info/err/log` accept varargs and join supported values with spaces
- Use `string.format(...)` first when placeholder formatting is needed

Reject this invented shape:
- `log.err('download failed: %s', err)`
