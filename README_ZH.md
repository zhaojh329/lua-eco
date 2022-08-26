# lua-eco

[1]: https://img.shields.io/badge/开源协议-MIT-brightgreen.svg?style=plastic
[2]: /LICENSE
[3]: https://img.shields.io/badge/提交代码-欢迎-brightgreen.svg?style=plastic
[4]: https://github.com/zhaojh329/lua-eco/pulls
[5]: https://img.shields.io/badge/提问-欢迎-brightgreen.svg?style=plastic
[6]: https://github.com/zhaojh329/lua-eco/issues/new
[7]: https://img.shields.io/badge/发布版本-1.0.0-blue.svg?style=plastic
[8]: https://github.com/zhaojh329/lua-eco/releases
[9]: https://github.com/zhaojh329/lua-eco/workflows/build/badge.svg
[11]: https://img.shields.io/badge/技术交流群-点击加入：153530783-brightgreen.svg
[12]: https://jq.qq.com/?_wv=1027&k=5PKxbTV

[![license][1]][2]
[![PRs Welcome][3]][4]
[![Issue Welcome][5]][6]
[![Release Version][7]][8]
![Build Status][9]
![visitors](https://visitor-badge.laobi.icu/badge?page_id=zhaojh329.lua-eco)
[![Chinese Chat][11]][12]

[libev]: http://software.schmorp.de/pkg/libev.html

Lua-eco 是一个基于 `IO` 事件机制实现的 Lua 协程库。包括 time, socket, ssl, dns, ubus, ip, iw, 以及未来将添加更多的模块。

想试试吗？很有趣的!

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

## 依赖
* [libev] - 高性能的事件循环库

## 编译

    sudo apt install -y liblua5.3-dev lua5.3 libev-dev libmnl-dev libssl-dev
    git clone --recursive https://github.com/zhaojh329/lua-eco.git
    cd lua-eco && mkdir build && cd build
    cmake .. && sudo make install

## [文档](DOC_ZH.md)

## 贡献代码
如果您想帮助 lua-eco 变得更好，请参考 [CONTRIBUTING_ZH.md](/CONTRIBUTING_ZH.md)。
