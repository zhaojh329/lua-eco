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

[lua]: https://www.lua.org
[libev]: http://software.schmorp.de/pkg/libev.html
[lua-mosquitto]: https://github.com/flukso/lua-mosquitto
[ubus]: https://openwrt.org/docs/techref/ubus

Lua-eco 是一个内置了 [libev] 事件循环的 [Lua] 解释器。它使所有的 [Lua] 代码在 `Lua协程` 中运行，它
可以挂起执行 `I/O` 操作的代码，直到数据准备好。这允许您编写代码就好像您在使用阻塞 `I/O` 一样，同时在
您等待 `I/O` 时仍然允许其它协程中的代码运行。这很像 `Goroutines`。

Lua-eco 还提供了一些有用的模块:

* time - 显示当前时间; 睡眠; 定时器
* file - open/close/read/write; access; readlink; stat; statvfs; chown; 遍历目录
* sys - exec; signal
* socket - tcp/tcp6; udp/udp6; unix
* ssl - 包括客户端和服务器
* http/https - 包括客户端和服务器
* mqtt - 客户端，使用 [lua-mosquitto]
* dns
* termios
* ubus - 对 [ubus] 的 Lua 绑定
* base64
* ...

想试试吗？很有趣的!

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

## 依赖
* [libev] - 高性能的事件循环库

## 编译

    sudo apt install -y liblua5.3-dev lua5.3 libev-dev libssl-dev
    git clone --recursive https://github.com/zhaojh329/lua-eco.git
    cd lua-eco && mkdir build && cd build
    cmake .. && sudo make install

## TODO

- [ ] websocket

## 贡献代码
如果您想帮助 lua-eco 变得更好，请参考 [CONTRIBUTING_ZH.md](/CONTRIBUTING_ZH.md)。
