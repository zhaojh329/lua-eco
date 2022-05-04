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

[libev]: http://software.schmorp.de/pkg/libev.html

Lua-eco is a `Lua coroutine` library which was implemented based on `IO event`.
Including time, socket, ssl, dns, ubus, ip, iw, and more which will be added in the future.

Would you like to try it? Kinda interesting.

```lua
local eco = require "eco"
local time = require "eco.time"
local socket = require "eco.socket"

local function handle_client(c)
    while true do
        local data, err = c:recv()
        if not data then
            print(err)
            break
        end
        c:send(data)
    end
end

eco.run(
    function()
        local s = socket.tcp()
        local ok, err = s:bind(nil, 8080)
        if not ok then
            error(err)
        end

        s:listen()

        while true do
            local c = s:accept()
            local peer = c:getpeername()
            print("new connection:", peer.ipaddr, peer.port)
            eco.run(handle_client, c)
        end
    end
)

eco.run(
    function()
        while true do
            print(time.now())
            time.sleep(1.0)
        end
    end
)

eco.loop()
```

## Requirements
* [libev] - A full-featured and high-performance event loop

## Build

    sudo apt install -y liblua5.3-dev lua5.3 libev-dev libmnl-dev libssl-dev
    git clone --recursive https://github.com/zhaojh329/lua-eco.git
    cd lua-eco && mkdir build && cd build
    cmake .. && make install

## [Reference](REFERENCE.md)

## Contributing
If you would like to help making [lua-eco](https://github.com/zhaojh329/lua-eco) better,
see the [CONTRIBUTING.md](https://github.com/zhaojh329/lua-eco/blob/master/CONTRIBUTING.md) file.
