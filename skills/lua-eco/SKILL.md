---
name: lua-eco
description: International lua-eco public API skill for writing, reviewing, explaining, and fixing Lua 5.4 code that runs on the eco runtime. Use when tasks mention lua-eco, eco runtime, coroutine scheduling, async I/O, sockets, HTTP/WebSocket/MQTT, DNS, files, processes, timers, ubus/UCI, netlink, nl80211, termios, SSH, encoding, hashing, or code review for scheduler safety, API selection, timeouts, and cleanup.
---

# lua-eco Public API Skill

## Scope
Use this skill when the user asks to:
- Write new lua-eco code, refactor existing code, fix bugs, or add tests.
- Look up or use any public eco API.
- Review code that is intended to run on lua-eco.

Trigger matching should use English public API names and domain terms. Activate this skill when the task mentions topics such as lua-eco, eco runtime, Lua 5.4, coroutine scheduler, async IO, network programming, socket, timeout, cleanup, code review, blocking misuse, or API selection.

This skill uses public APIs only by default and must not guide users toward direct dependencies on eco.internal modules.

## Dual Workflow
### Mode A: Code Generation
1. Read the runtime model when generating complete programs or reviewing scheduler behavior.
2. If the user is starting from zero and asks for a complete program, apply the program skeleton.
3. Identify capabilities first: concurrency, files, processes, networking, protocols, or platform integration.
4. Select API candidates from the reference files, including primary and fallback module families.
5. Run the Symbol Gate: verify every function, method, and constant against the public API manifest.
6. Run the Shape Gate for covered high-risk modules: verify return values, object fields, and handler signatures against `references/95-high-risk-api-shapes.md`.
7. Run the Signature Gate: use the API quick reference for call signatures, option names, summaries, and official documentation URLs.
8. Run the Example Gate: inspect the closest runnable examples or tests for the selected module family before generating nontrivial call shapes.
9. Generate code with eco-scheduler-friendly patterns, timeouts, error handling, and resource cleanup.
10. Run the Output Gate: reject invented fields, return shapes, or cross-ecosystem habits before answering.

### Mode B: Code Review
1. Start with findings ordered by severity: Critical, High, Medium, Low.
2. Each finding must include trigger conditions, risk, recommended fix, and whether tests are needed.
3. Review these dimensions first:
- Whether API selection matches the task capability.
- Whether field names, return tuples, and handler signatures match documented lua-eco shapes.
- Whether blocking interfaces are misused in a way that breaks eco scheduling.
- Whether timeout handling and nil, err checks are missing.
- Whether sockets, files, processes, timers, or connection contexts can leak.
- Whether boundary inputs and error paths are covered by tests.

## Routing Guard
This skill does not rely on hard-coded one-off function choices. It uses a general routing mechanism:
1. Capability matrix: map the task to one or more capabilities before selecting APIs.
2. Primary and secondary strategy: each capability defines primary and secondary API families.
3. Anti-pattern constraints: each capability defines common misuse cases.
4. Symbol gate: do not output calls to functions missing from the public API manifest.
5. Shape gate: do not output fields, return tuples, or handler signatures that are not documented for lua-eco.
6. Signature gate: use the API quick reference before emitting calls with nontrivial arguments.
7. Example gate: prefer the closest runnable examples or tests for covered high-risk modules before trusting generic intuition.
8. Fallback rewrite: if the selected API does not match the capability, backtrack and rewrite before answering.

Detailed rules: references/10-capability-matrix-and-routing-guards.md.

## Evidence Priority
When sources disagree or generic intuition conflicts with lua-eco, resolve facts in this order:
1. Public symbol existence: `references/90-public-api-manifest.md`
2. High-risk object shapes and return conventions: `references/95-high-risk-api-shapes.md`
3. Runnable examples and tests in the lua-eco repo
4. API signatures and option names: `references/91-api-quick-reference.md`
5. Source inspection as a tie-breaker only when earlier layers do not settle the answer

Never infer field names or return structures from Python requests, Fetch, Node.js streams, Go net/http, or other ecosystems when lua-eco evidence is available.

## Runtime and Syntax Constraints
- Run programs with eco by default, not lua.
- Use luac5.4 -p for syntax checks.
- If `luac5.4` is unavailable, first check whether plain `luac` exists and reports Lua 5.4; use it only in that case.
- If no Lua 5.4 compiler is available, try to install one with the system package manager instead of failing immediately.
- If installation requires network access or elevated permissions, request user approval and then proceed with the install attempt.
- Prefer coroutine-scheduler-friendly APIs.
- Avoid long blocking calls on primary coroutine paths.

## Reference Entry Points
- Activation and global rules: references/00-activation-and-global-rules.md
- Runtime model: references/00-runtime-model.md
- Core and concurrency: references/01-core-and-concurrency.md
- Files, processes, and system IO: references/02-files-processes-system.md
- Networking and transport: references/03-networking-and-transport.md
- HTTP, WebSocket, and MQTT: references/04-http-websocket-mqtt.md
- Platform integration and devices: references/05-platform-integration-and-devices.md
- Netlink family: references/06-netlink-family.md
- Encoding and digests: references/07-encoding-and-digests.md
- API coverage checklist: references/08-api-coverage-checklist.md
- Code review template: references/09-code-review-template.md
- Capability matrix and routing guards: references/10-capability-matrix-and-routing-guards.md
- Regression prompts: references/11-regression-prompts.md
- Public API manifest: references/90-public-api-manifest.md
- API quick reference: references/91-api-quick-reference.md
- High-risk API shapes: references/95-high-risk-api-shapes.md
- Usage patterns: references/92-usage-patterns.md
- Common mistakes: references/93-common-mistakes.md
- Program skeleton: references/94-program-skeleton.md

## Minimum Delivery Standard
- Generated code must be runnable, readable, maintainable, and include error handling plus resource cleanup.
- Code reviews must be finding-first, evidence-based, and actionable.
- API selection must match the required capability and avoid nonexistent or unsuitable functions.
- Covered high-risk modules must use the documented lua-eco field names, return tuples, and handler signatures.
