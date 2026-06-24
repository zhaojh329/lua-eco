# Capability Matrix and Routing Guards

Goal: make API selection generalizable instead of relying on one-off function special cases.

## General Selection Flow
1. Identify task capabilities. Multiple capabilities may apply.
2. Select the Primary API family.
3. If the Primary family is unavailable, select the Secondary family only under the documented conditions.
4. Check Anti-pattern entries and reject cross-capability mismatches.
5. Run the Symbol Gate before generating code.
6. Run the Shape Gate before emitting object-field access, tuple unpacking, or handler signatures.
7. Run the Signature Gate before emitting nontrivial call shapes or option tables.
8. Run the Example Gate before trusting generic intuition for covered high-risk modules.
9. Run the Output Gate before answering.

## Capability Matrix

### Capability A: Plain TCP Client or Server
- Primary: eco.socket.connect_tcp / listen_tcp
- Secondary: eco.socket.tcp plus bind/connect/listen
- Anti-pattern: using HTTP APIs to implement a raw TCP protocol

### Capability B: HTTP Requests and Services
- Primary: eco.http.client / eco.http.server
- Secondary: none, unless the task explicitly asks for a handwritten protocol implementation
- Anti-pattern: replacing complete HTTP semantic handling with raw socket code

### Capability C: TLS Secure Transport
- Primary: eco.ssl
- Secondary: eco.socket plus a custom wrapper only when explicitly required by the task
- Anti-pattern: emitting plaintext socket code when TLS is required

### Capability D: Link-Layer Packet Capture or Injection
- Primary: eco.socket AF_PACKET capabilities plus eco.packet
- Secondary: task-specific only
- Anti-pattern: confusing device tunneling with link-layer packet capture

### Capability E: TUN/TAP Devices
- Primary: eco.socket.open_tun
- Secondary: none
- Anti-pattern: using raw sockets as a substitute for creating tunnel devices

### Capability F: Message Bus or Configuration Store
- Primary: eco.ubus / eco.uci
- Secondary: none
- Anti-pattern: replacing structured APIs with shell command string assembly

### Capability G: Wireless or Routing Kernel Interaction
- Primary: eco.nl / eco.genl / eco.rtnl / eco.nl80211 / eco.ip
- Secondary: none
- Anti-pattern: assuming parsing succeeded without checking message types

## Anti-pattern Driven Strategy
- Each capability lists an incorrect selection example.
- If generated output matches an anti-pattern, trigger a fallback rewrite.
- After fallback rewrite, re-check symbol availability and capability fit.

## Symbol Gate
- Before generation, confirm that the function or method exists in references/90-public-api-manifest.md.
- The manifest is a stable public API allowlist. It must not depend on source filenames or line numbers.
- If a symbol is not found, do not generate call code. Explain the limitation and provide candidates instead.

## Shape Gate
- Before generation, confirm return tuples, object fields, and handler signatures against references/95-high-risk-api-shapes.md when the target module is covered there.
- For covered modules, do not infer shapes from Python requests, Fetch, Node streams, Go net/http, or other familiar libraries.
- If the high-risk reference does not settle the answer, inspect runnable examples/tests before generating the shape.
- If a field, tuple, or handler signature is still not evidenced, do not invent it. Rewrite the answer conservatively or explain the limitation.

## Signature Gate
- Use references/91-api-quick-reference.md for signatures, summaries, constants, table types, and official documentation URLs.
- If quick reference and a hand-written guide disagree, prefer the generated quick reference for exact signatures and prefer the hand-written guide for capability selection.

## Example Gate
- For covered high-risk modules, inspect the closest runnable example or test before generating nontrivial code.
- Prefer repo examples and tests that exercise the exact function family over generic summaries.
- If examples and quick reference diverge on object shapes, trust the documented high-risk shape file first, then runnable examples/tests, then inspect source.

## Output Gate
- Re-scan the draft answer for invented fields, return tuples, event names, or option keys.
- Reject drafts containing cross-ecosystem habits such as `resp.status_code`, callback-only WebSocket APIs, or direct stdout/stderr fields on `sys.exec` return values.
- Only answer after the draft passes Symbol Gate, Shape Gate, Signature Gate, and Example Gate.

## Evidence Priority
1. Public API existence: references/90-public-api-manifest.md
2. High-risk response shapes and return conventions: references/95-high-risk-api-shapes.md
3. Runnable repo examples and tests
4. API quick reference for signatures and option names: references/91-api-quick-reference.md
5. Source inspection as a tie-breaker only when earlier layers do not settle the answer
