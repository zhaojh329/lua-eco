# HTTP and Messaging Protocols

## Module eco.http.url
- escape
- unescape
- parse

## Module eco.http.client
Top-level functions:
- new
- request
- get
- post
- body_with_file
- form

client methods:
- close
- sock
- request

Response shape and usage:
- Request helpers return `resp, err`.
- Successful response objects use `resp.code`, `resp.status`, `resp.headers`, and optional `resp.body`.
- When `body_to_file` is used, body content is written to the file path and `resp.body` may be absent.
- Use runnable examples as anchors: `examples/http/get.lua`, `examples/http/post.lua`, `examples/http/download_file.lua`.
- Do not invent fields such as `resp.status_code`, `resp.statusCode`, `resp.ok`, or `resp.text()`.

body_form methods:
- add
- add_file

## Module eco.http.server
- listen

connection methods:
- remote_addr
- add_header
- set_status
- send_error
- redirect
- send
- send_file
- flush
- read_body
- read_formdata
- discard_body
- serve_file

Handler and request shape:
- `listen(..., handler)` calls `handler(con, req)`.
- `req` is a plain table whose common fields include `method`, `raw_path`, `path`, `headers`, `query`, `query_string`, and `form`.
- Use `con:set_status`, `con:add_header`, `con:send_error`, `con:discard_body`, and related connection methods instead of fabricating a response object API.

## Module eco.websocket
- upgrade
- connect

connection methods:
- recv_frame
- send_frame
- send_text
- send_binary
- send_close
- send_ping
- send_pong

Connection shape:
- `websocket.connect(...)` returns `ws, err`.
- `ws:recv_frame([timeout])` returns `data, typ, err`; `typ` is the frame type, not a field on `data`.
- `ws:send_text/send_binary/send_ping/send_pong/send_close` return `bytes, err`.
- Use runnable examples as anchors: `examples/websocket/client.lua`, `examples/websocket/server.lua`.

## Module eco.mqtt
Top-level functions:
- mqtt.new

Common client capabilities:
- Event callback registration
- Connection setup and run loop
- Subscribe and unsubscribe
- Publish and reconnect handling

Client and event shape:
- `mqtt.new([opts])` returns a client object; reconnect loops are driven by caller code around `client:run()`.
- `client:on(event, handler)` and `client:on({ ... })` are the supported registration forms.
- Example event handler signatures: `conack(ack, client)`, `suback(ack)`, `unsuback(topic)`, `publish(msg, client)`, `error(err)`.
- Use `examples/mqtt.lua` as the primary evidence source for event names and payload fields.

## Review Focus
- HTTP: request body handling and connection reuse.
- HTTP: response field names must match lua-eco examples and references.
- WebSocket: complete ping, pong, and close protocol state handling.
- WebSocket: multi-value return conventions must not be collapsed into fabricated message objects.
- MQTT: keepalive, reconnect behavior, and QoS semantics aligned with requirements.
- MQTT: event names and handler signatures must come from lua-eco evidence, not other client libraries.
