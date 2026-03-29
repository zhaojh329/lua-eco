# Copilot Instructions For lua-eco

## Scope
These rules apply to all work in this repository.

## Runtime And Execution
- Treat this project as eco runtime first, not generic Lua runtime.
- Run scripts, examples, and tests with eco by default.
- Do not use lua to run repository scripts or tests unless the user explicitly asks for it.
- At script top level, do not add manual eco.loop startup logic unless the user explicitly asks for it.

## Lua Version Baseline
- Use Lua 5.4 as the only language baseline for all code writing, code review, debugging, behavior reasoning, and API assumptions.
- Follow the full Lua 5.4 specification and standard library behavior, not a subset of selected features.
- Do not write or suggest compatibility workarounds for other Lua versions unless the user explicitly requests multi-version support.

## Syntax Check And Local Validation
- Use luac5.4 for Lua syntax validation.
- Preferred command format: luac5.4 -p path/to/file.lua
- Do not use luac for syntax checks in this repository.
- If luac5.4 is unavailable in the environment, install Lua 5.4 first using apt:
	- sudo apt install lua5.4
- Note that sudo apt install may prompt for the current user's password in the terminal.
- If apt is unavailable or installation is not permitted, state that clearly and ask before using alternatives.

## IO And Concurrency Model
- Prefer eco modules for IO, timing, process control, and networking because they are coroutine scheduler aware.
- Avoid introducing blocking patterns that break the eco coroutine scheduling model when equivalent eco APIs exist.
- Do not use APIs that can block the process for a long time, including os.execute and io.popen.
- When using `sys.sh`, prefer the table form (for example `sys.sh({ 'echo', 'hello' })`) over the string form when shell syntax is not required. This avoids shell parsing semantics such as comments, quoting, and expansion side effects, and it skips the extra `/bin/sh -c` process.
- Use string-form `sys.sh('...')` only when shell behavior is intentional, for example redirection, pipelines, compound commands, or shell expansion.
- Avoid long-running synchronous standard io.* operations on slow devices or large files in latency-sensitive paths.
- Avoid unbounded CPU or memory-heavy operations in the main coroutine, including huge string.rep calls, very large concatenation loops, and large in-coroutine sort/transform workloads.
- Prefer eco scheduler-aware alternatives (for example eco.sys and eco.file), and split heavy CPU work into bounded chunks or move it out of latency-sensitive coroutine paths.

## Native Module Workflow
- When changing C modules or Lua C bridge code, review related build wiring in CMakeLists and matching Lua wrappers before editing.
- After native changes, rebuild and validate behavior before concluding.
- Avoid mixing system installed module results with workspace build results when validating fixes.

## Command Defaults
- Prefer repository relative commands and existing entry points under tests and examples.
- For test execution, prefer existing runnable test scripts with eco.

## Correct Vs Incorrect Examples
Correct:
- eco tests/dns-test.lua
- eco examples/timer.lua
- luac5.4 -p dns.lua
- Use eco.sys APIs for process execution in runtime code paths.
- sys.sh({ 'echo', 'hello' }) for simple command execution.
- sys.sh({ 'ip', 'link', 'show' }) instead of sys.sh('ip link show') when shell syntax is not needed.

Incorrect:
- lua tests/dns-test.lua
- lua examples/timer.lua
- luac -p dns.lua
- os.execute("...") or io.popen("...") in latency-sensitive coroutine paths.
- sys.sh('echo hello') for simple command execution that does not need shell syntax.
