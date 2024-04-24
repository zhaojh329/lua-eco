# lua-eco

[1]: https://img.shields.io/badge/开源协议-MIT-brightgreen.svg?style=plastic
[2]: /LICENSE
[3]: https://img.shields.io/badge/提交代码-欢迎-brightgreen.svg?style=plastic
[4]: https://github.com/zhaojh329/lua-eco/pulls
[5]: https://img.shields.io/badge/提问-欢迎-brightgreen.svg?style=plastic
[6]: https://github.com/zhaojh329/lua-eco/issues/new
[7]: https://img.shields.io/badge/发布版本-3.4.1-blue.svg?style=plastic
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
[ubus]: https://openwrt.org/docs/techref/ubus

Lua-eco 是一个内置了事件循环的 Lua 解释器。它能够自动调度轻量级 `Lua 协程`, 从而实现在 Lua 中的高效并发。使用 Lua-eco 可以构建高性能、可扩展的应用程序。

Lua-eco 还提供了一些有用的模块，方便您快速构建应用程序:

* `log`: 为 lua-eco 应用程序提供日志功能，允许您以不同的级别打印日志并将其输出到各种目的地。
* `time`: 提供了一个 Lua 接口，用于获取系统时间，休眠，执行定时器操作。
* `file`: 提供了一个 Lua 接口，允许您读写入文件，遍历目录以及执行其他与文件相关的操作。
* `sys`: 提供了对各种系统级功能的访问，例如进程ID，系统信息，同时允许您执行shell命令并获取其退出状态以及标准输出和标准错误输出。
* `socket`: 提供了一组网络套接字接口，允许您创建和管理网络连接。包括 tcp，tcp6，udp，udp6 和 unix。
* `ssl`: 为 Lua-eco 应用程序提供了 SSL/TLS 支持，允许您建立与远程服务器的安全连接。
* `http/https`: 为 Lua-eco 应用程序提供了 HTTP(S) 客户端和服务器实现。
* `websocket`: 为 Lua-eco 应用程序提供了一个 WebSocket 客户端和服务器实现，允许您构建实时 Web 应用程序。
* `mqtt`: 为 Lua-eco 应用程序提供了一个 MQTT 3.1.1 协议的实现。
* `dns`: 为 Lua-eco 应用程序提供了一个 DNS 客户端实现，允许您执行 DNS 查找和解析域名。
* `ubus`: 提供了一个 Lua 接口，用于 OpenWrt 中的 [ubus] 系统，允许您与系统服务和守护程序交互。
* `sync`: 提供了协程间同步的操作。
* `netlink`: 为内核和用户空间进程之间的进程间通信（IPC）提供操作。
* `nl80211`: 显示/操作无线设备及其配置。
* `termios`: 绑定 unix 接口用于操作终端和串口。
* `ssh`: 绑定 libssh2.

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

### Ubuntu

    sudo apt install -y liblua5.3-dev lua5.3 libev-dev libssl-dev
    git clone --recursive https://github.com/zhaojh329/lua-eco.git
    cd lua-eco && mkdir build && cd build
    cmake .. && sudo make install

### OpenWrt

    Languages  --->
        Lua  --->
            -*- lua-eco............... A Lua interpreter with a built-in libev event loop
            -*- lua-eco-base64................................ base64 support for lua-eco
             -*- lua-eco-dns...................................... dns support for lua-eco
             -*- lua-eco-http.............................. http/https support for lua-eco
             -*- lua-eco-log................................ log utils support for lua-eco
             <*> lua-eco-mqtt.................................... mqtt support for lua-eco
             <*> lua-eco-network.............................. network support for lua-eco
             -*- lua-eco-sha1.................................... sha1 support for lua-eco
             -*- lua-eco-socket................................ socket support for lua-eco
             -*- lua-eco-ssl...................................... ssl support for lua-eco
                SSL Library (mbedTLS)  --->
            <*> lua-eco-termios............................... termios support for lua-eco
            -*- lua-eco-ubus..................................... ubus support for lua-eco
            <*> lua-eco-websocket........................... websocket support for lua-eco
            <*> lua-eco-netlink............................... netlink support for lua-eco
            <*> lua-eco-nl80211............................... nl80211 support for lua-eco
