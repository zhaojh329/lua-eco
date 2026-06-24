# Activation and Global Rules

## When to Activate
Activate this skill when the task involves any of these topics:
- eco, lua-eco, eco runtime, Lua 5.4, coroutine scheduler, async IO
- socket, network programming, ssl, dns, http, websocket, mqtt
- ubus, uci, netlink, nl80211, termios
- encoding, hash, shared memory, process control
- code review, blocking misuse, performance risk, timeout, resource leak, API selection

## Global Rules
1. Language and runtime
- The language baseline is Lua 5.4.
- The default runtime entry point is eco.
- Complete from-zero programs must use the program skeleton unless the user asks for a snippet, module, or test.

2. API usage
- Use public APIs only.
- Do not add direct dependencies on eco.internal modules.
- Verify symbols before generation and do not invent functions.
- Use the API quick reference for signatures and official documentation URLs.
- Do not infer field names, response shapes, or handler signatures from other language ecosystems.
- For covered modules, consult `references/95-high-risk-api-shapes.md` before generating object-field access or multi-value unpacking.
- When examples or tests exist for the target module, use them as evidence before relying on generic habits.

3. Scheduler safety
- Avoid long blocking calls that can break coroutine scheduling.
- External IO operations should include timeout and error branches.

4. Error handling
- Consistently handle nil, err return conventions.
- Error messages should be specific enough to diagnose and act on.

5. Resource management
- Explicitly close sockets, files, processes, timers, and connection objects.
- Cleanup logic should be idempotent.

6. Verification tooling
- Use `luac5.4 -p` for Lua syntax checks when verifying generated or modified code.
- If `luac5.4` is missing, use plain `luac -p` only when `luac -v` confirms Lua 5.4.
- If no suitable Lua 5.4 bytecode compiler is installed, attempt installation with the host package manager rather than stopping at "command not found".
- If installation needs network access, package-manager writes, or elevated permissions, ask the user for approval through the normal command-approval path before proceeding.

7. Evidence priority
- Symbol existence comes from `references/90-public-api-manifest.md`.
- High-risk response and object shapes come from `references/95-high-risk-api-shapes.md`, then runnable examples/tests.
- Signatures and option names come from `references/91-api-quick-reference.md`.
- If evidence is still incomplete, inspect source and answer conservatively instead of inventing fields or behaviors.

## Code Review Severity
- Critical: crashes, data corruption, security vulnerabilities, or severe scenario mismatch.
- High: likely failures, leaks, uncontrolled timeouts, or concurrency races.
- Medium: weak robustness, missing boundary handling, or test gaps.
- Low: maintainability, naming, comments, or structure improvements.
