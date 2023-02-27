# lua-eco([中文](/README_ZH.md))

[1]: https://img.shields.io/badge/license-MIT-brightgreen.svg?style=plastic
[2]: /LICENSE
[3]: https://img.shields.io/badge/PRs-welcome-brightgreen.svg?style=plastic
[4]: https://github.com/zhaojh329/lua-eco/pulls
[5]: https://img.shields.io/badge/Issues-welcome-brightgreen.svg?style=plastic
[6]: https://github.com/zhaojh329/lua-eco/issues/new
[7]: https://img.shields.io/badge/release-1.0.0-blue.svg?style=plastic
[8]: https://github.com/zhaojh329/lua-eco/releases
[9]: https://github.com/zhaojh329/lua-eco/workflows/build/badge.svg

[![license][1]][2]
[![PRs Welcome][3]][4]
[![Issue Welcome][5]][6]
[![Release Version][7]][8]
![Build Status][9]
![visitors](https://visitor-badge.laobi.icu/badge?page_id=zhaojh329.lua-eco)

[lua]: https://www.lua.org
[libev]: http://software.schmorp.de/pkg/libev.html
[lua-mosquitto]: https://github.com/flukso/lua-mosquitto
[ubus]: https://openwrt.org/docs/techref/ubus

Lua-eco is a [Lua] interpreter with a built-in [libev] event loop. It makes
all [Lua] code running in `Lua coroutines` so code that does I/O can be
suspended until data is ready. This allows you write code as if you're using
blocking I/O, while still allowing code in other coroutines to run when you'd
otherwise wait for I/O. It's kind of like `Goroutines`.

Lua-eco also provides some modules for you to build applications quickly:

* `log`: Provides logging functionality for Lua-eco applications, allowing you to log messages at different severity levels and output them to various destinations.
* `time`: Provides a Lua interface, allowing you to get current time, sleeping, performing timer operations.
* `file`: Provides a Lua interface, allowing you to read and write files, traverse directory and perform other file-related operations.
* `sys`: Provides access to various system-level functionality, such as process id, system information, and allows you to execute shell commands while obtaining their exit status as well as their standard output and standard error output.
* `socket`: Provides a low-level network socket interface for Lua-eco applications, allowing you to create and manage network connections. Includes tcp, tcp6, udp, udp6 and unix.
* `ssl`: Provides SSL/TLS support for Lua-eco applications, allowing you to establish secure connections to remote servers.
* `http/https`: Provides a HTTP client and server implementation for Lua-eco applications.
* `websocket`: Provides a WebSocket server implementation for Lua-eco applications, allowing you to build real-time web applications.
* `mqtt`: Provides an implementation of the MQTT protocol for Lua-eco applications using [lua-mosquitto], allowing you to build IoT and messaging applications.
* `dns`: Provides a DNS client implementation for Lua-eco applications, allowing you to perform DNS lookups and resolve domain names.
* `ubus` - Provides a Lua interface to the [ubus] system in OpenWrt, allowing you to interact with system services and daemons.

Would you like to try it? Kinda interesting.

```lua
#!/usr/bin/env eco

local time = require 'eco.time'

eco.run(function(name)
    while true do
        print(time.now(), name, eco.id())
        time.sleep(1.0)
    end
end, 'eco1')

eco.run(function(name)
    while true do
        print(time.now(), name, eco.id())
        time.sleep(2.0)
    end
end, 'eco2')
```

## Requirements
* [libev] - A full-featured and high-performance event loop

## Build

    sudo apt install -y liblua5.3-dev lua5.3 libev-dev libssl-dev
    git clone --recursive https://github.com/zhaojh329/lua-eco.git
    cd lua-eco && mkdir build && cd build
    cmake .. && sudo make install

## Contributing
If you would like to help making [lua-eco](https://github.com/zhaojh329/lua-eco) better,
see the [CONTRIBUTING.md](https://github.com/zhaojh329/lua-eco/blob/master/CONTRIBUTING.md) file.
