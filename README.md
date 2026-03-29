# lua-eco([中文](README_ZH.md))

[1]: https://img.shields.io/badge/license-MIT-brightgreen.svg?style=plastic
[2]: LICENSE
[3]: https://img.shields.io/badge/PRs-welcome-brightgreen.svg?style=plastic
[4]: https://github.com/zhaojh329/lua-eco/pulls
[5]: https://img.shields.io/badge/Issues-welcome-brightgreen.svg?style=plastic
[6]: https://github.com/zhaojh329/lua-eco/issues/new
[7]: https://img.shields.io/badge/release-3.18.0-blue.svg?style=plastic
[8]: https://github.com/zhaojh329/lua-eco/releases
[9]: https://github.com/zhaojh329/lua-eco/workflows/build/badge.svg

[![license][1]][2]
[![PRs Welcome][3]][4]
[![Issue Welcome][5]][6]
[![Release Version][7]][8]
![Build Status][9]
[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/zhaojh329/lua-eco)
![visitors](https://visitor-badge.laobi.icu/badge?page_id=zhaojh329.lua-eco)

[lua]: https://www.lua.org
[ubus]: https://openwrt.org/docs/techref/ubus

Lua-eco is a coroutine-first runtime environment for Lua 5.4.

At its core is an **I/O-event-driven coroutine scheduler** (Linux `epoll` + timers): all I/O APIs use **non-blocking file descriptors** under the hood while exposing a **synchronous** programming style in Lua.

This means you can write code like "connect -> read -> write -> sleep" in a single coroutine, and Lua-eco will automatically yield and resume it based on I/O readiness.

## Why lua-eco

- **Synchronous APIs, non-blocking internals**: write straightforward code (no callbacks or state machines); coroutines yield on `EAGAIN` and resume when ready.
- **High concurrency with lightweight coroutines**: run thousands of tasks in a single OS thread.
- **Practical built-in modules**: sockets, TLS, HTTP/WebSocket, MQTT, DNS, logging, filesystem, sync primitives, netlink, OpenWrt integrations, and more. All I/O modules share the same coroutine scheduler.

## Quick start

Lua-eco is designed to run Lua programs with the `eco` interpreter
(`#!/usr/bin/env eco`). The `eco` module is built into this interpreter.

When the `eco` interpreter starts:

- the `eco` module is loaded and injected into `_G` automatically.
- your entry script runs in a coroutine created internally via `eco.run(...)`.
- the scheduler starts internally via `eco.loop()`.

At script top level:

- you should not call `eco.loop()` yourself.
- you usually do not need to call `eco.run()` to wrap the entry script.
- you may still call `local eco = require 'eco'`; it returns the already loaded `_G.eco`.
    This is useful for avoiding Lua LSP warnings such as `Undefined global 'eco'`.

Minimal script:

```lua
#!/usr/bin/env eco

local time = require 'eco.time'

time.sleep(1.0)
print('hello from eco runtime')
```

Starting additional coroutines explicitly:

```lua
#!/usr/bin/env eco

local time = require 'eco.time'
local eco = require 'eco' -- optional: avoids LSP "Undefined global 'eco'"

eco.run(function(name)
    local co = coroutine.running()
    while true do
        print(time.now(), name, co)
        time.sleep(1.0)
    end
end, 'eco1')

eco.run(function(name)
    local co = coroutine.running()
    while true do
        print(time.now(), name, co)
        time.sleep(2.0)
    end
end, 'eco2')
```

Simple HTTPS request (still written synchronously):

```lua
#!/usr/bin/env eco

local http = require 'eco.http.client'
local eco = require 'eco' -- optional: avoids LSP "Undefined global 'eco'"

eco.run(function()
    local resp, err = http.get('https://example.com', { timeout = 10.0 })
    assert(resp, err)
    print('status:', resp.code)
    print(resp.body)
end)
```

## How it works

- Lua-eco creates non-blocking FDs for sockets/files.
- When a coroutine calls an I/O method and the FD is not ready, Lua-eco registers the FD in `epoll`, then yields.
- The main loop waits for readiness/timers and resumes the coroutine automatically.

As long as you use lua-eco modules, your I/O code naturally follows a concurrent model with automatic coroutine scheduling.

## Modules

Core primitives:

- `eco`: scheduler (`run`, `loop`, `sleep`, `io`, `reader`, `writer`, ...)
- `time`: timers and time helpers
- `log`: structured logging
- `sys`: signals, process utilities, spawn/exec helpers
- `file`: filesystem helpers + inotify wrappers
- `sync`: coroutine sync primitives (cond/mutex/...)
- `channel`: coroutine communication channel

Networking:

- `socket`: TCP/UDP/UNIX/ICMP/raw packet sockets
- `ssl`: TLS client/server built on top of TCP sockets (OpenSSL/WolfSSL/MbedTLS backend)
- `http`: HTTP client/server (`eco.http.client`, `eco.http.server`, `eco.http.url`)
- `websocket`: WebSocket client/server (HTTP upgrade)
- `mqtt`: MQTT 3.1.1 client implementation
- `dns`: UDP DNS resolver

Linux / system integrations:

- `packet`: low-level packet construction/parsing helpers
- `nl`, `genl`, `rtnl`, `nl80211`: netlink helpers and Wi-Fi (nl80211)
- `termios`: terminal/serial I/O bindings
- `ip`, `net`: network utilities built on top of netlink/socket
- `shared`: shared-memory dictionary over `mmap(MAP_SHARED)` (`/dev/shm`)

OpenWrt:

- `ubus`: integration with OpenWrt [ubus]
- `uci`: bindings for UCI config (optional)

Hash / encoding:

- `eco.hash`: `md5`, `sha1`, `sha256`, `hmac`
- `eco.encoding`: `base64`, `hex`

## Requirements

- Linux (Lua-eco scheduler uses `epoll`)
- Lua 5.4

Optional dependencies (auto-detected; missing deps will skip the module):

- TLS backend: OpenSSL, WolfSSL, or MbedTLS
- `ubus`: libubus + libubox (+ json-c)
- `uci`: libuci
- `ssh`: libssh2

## Build

### Ubuntu

    sudo apt install -y liblua5.4-dev
    git clone --recursive https://github.com/zhaojh329/lua-eco.git
    cd lua-eco && mkdir build && cd build
    cmake .. && sudo make install

If you want TLS support via OpenSSL on Ubuntu:

    sudo apt install -y libssl-dev

Disable optional modules if you don't need them:

    cmake .. -DECO_SSL_SUPPORT=OFF -DECO_UBUS_SUPPORT=OFF -DECO_UCI_SUPPORT=OFF -DECO_SSH_SUPPORT=OFF

### OpenWrt

    Languages  --->
        Lua  --->
            -*- lua-eco............... A Lua interpreter with a built-in event loop
            -*- lua-eco-base64................................ base64 support for lua-eco
             -*- lua-eco-dns...................................... dns support for lua-eco
             -*- lua-eco-file.............................. file utils support for lua-eco
             -*- lua-eco-http.............................. http/https support for lua-eco
             -*- lua-eco-log................................ log utils support for lua-eco
             <*> lua-eco-mqtt.................................... mqtt support for lua-eco
             <*> lua-eco-network.............................. network support for lua-eco
             -*- lua-eco-sha1.................................... sha1 support for lua-eco
             -*- lua-eco-socket................................ socket support for lua-eco
             -*- lua-eco-ssl...................................... ssl support for lua-eco
                SSL Library (mbedTLS)  --->
            ......

## Documentation

- Browse the generated API docs at https://zhaojh329.github.io/lua-eco/.
- See runnable scripts in [examples](examples) and [tests](tests).

## ❤️ [Donation](https://zhaojh329.github.io/zhaojh329/)
