# Program Skeleton

Use this when generating a complete lua-eco program from zero.

## When Required
- Apply this skeleton by default for complete scripts, services, daemons, tools, clients, and servers.
- Skip it only when the user explicitly asks for a minimal snippet, a function, a library module, a test case, or code to fit into an existing program.

## Required Shape

```lua
local cli = require 'eco.cli'
local log = require 'eco.log'
local eco = require 'eco'

local function trace_hook(event)
    local info3 = debug.getinfo(3, 'Sl')

    if not info3 then
        return
    end

    local info2 = debug.getinfo(2, 'nf')

    local src = info3.short_src

    if info3.currentline ~= -1 then
        src = src .. ':' .. info3.currentline
    end

    log.info(event:upper(), info2.name or info2.func, src)
end

local function main()
    local opts, err = cli.parse_args({
        { name = 'trace' },
        -- Add task-specific options here.
    })
    if not opts then
        io.stderr:write(err, '\n')
        os.exit(1)
    end

    eco.set_panic_hook(function(traceback1, traceback2)
        log.err(traceback1)
        log.err(traceback2)
    end)

    log.set_flags(log.FLAG_LF | log.FLAG_FILE)
    log.set_ident('task-specific-ident')

    if opts.trace then
        debug.sethook(trace_hook, 'rc')
    end

    log.info('task-specific-ident run')

    -- Business logic goes here.
end

main()
```

## Adaptation Rules
- Replace `task-specific-ident` with a stable ident derived from the user task, such as `tcp-echo-server`, `mqtt-bridge`, or `ubus-monitor`.
- Put business logic inside `main()`.
- Add task-specific command-line options to `parse_args()` using `eco.cli.parse_args`; read positional arguments from `opts.args`.
- Use POSIX/GNU `getopt_long`-style option forms: long options use `--name`, short options are one-character `-x` aliases.
- Use `eco.run` inside `main()` for concurrent workers.
- Do not add `eco.loop()` for normal scripts; the `eco` interpreter starts the scheduler.
- Keep `--trace` support unless the user explicitly asks for a very small example.
- When building formatted log messages, call `string.format(...)` first; `eco.log` joins arguments with spaces and does not apply printf-style formatting.
