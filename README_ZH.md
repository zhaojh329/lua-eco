# lua-eco

[1]: https://img.shields.io/badge/开源协议-MIT-brightgreen.svg?style=plastic
[2]: /LICENSE
[3]: https://img.shields.io/badge/提交代码-欢迎-brightgreen.svg?style=plastic
[4]: https://github.com/zhaojh329/lua-eco/pulls
[5]: https://img.shields.io/badge/提问-欢迎-brightgreen.svg?style=plastic
[6]: https://github.com/zhaojh329/lua-eco/issues/new
[7]: https://img.shields.io/badge/发布版本-3.14.0-blue.svg?style=plastic
[8]: https://github.com/zhaojh329/lua-eco/releases
[9]: https://github.com/zhaojh329/lua-eco/workflows/build/badge.svg
[11]: https://img.shields.io/badge/技术交流群-点击加入：153530783-brightgreen.svg
[12]: https://jq.qq.com/?_wv=1027&k=5PKxbTV

[![license][1]][2]
[![PRs Welcome][3]][4]
[![Issue Welcome][5]][6]
[![Release Version][7]][8]
![Build Status][9]
[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/zhaojh329/lua-eco)
![visitors](https://visitor-badge.laobi.icu/badge?page_id=zhaojh329.lua-eco)
[![Chinese Chat][11]][12]

[lua]: https://www.lua.org
[ubus]: https://openwrt.org/docs/techref/ubus

Lua-eco 是一个面向协程并发的 Lua 5.4 运行环境。

它的核心能力是：**基于 I/O 事件自动调度 Lua 协程**（Linux `epoll` + 定时器）。所有 I/O API 底层都使用**非阻塞**文件描述符实现，但在 Lua 层暴露为**同步**写法：当 I/O 暂不可用时，当前协程会自动 `yield`，并在 fd 就绪或超时后自动恢复执行。

一句话：你可以用“同步代码”的直觉写网络/文件/系统程序，同时获得事件驱动的高并发。

## 为什么选择 lua-eco

- **同步写法，底层非阻塞**：无需回调/状态机；遇到 `EAGAIN` 自动挂起，fd 就绪或超时自动恢复。
- **单线程高并发**：大量轻量级协程并发执行，调度开销低。
- **模块齐全**：socket/TLS/HTTP/WebSocket/MQTT/DNS/netlink/日志/文件/协程同步互斥/哈希编码，以及 OpenWrt 集成（ubus/uci）等，并且 I/O 统一基于同一套自动协程调度机制。

## 快速上手

启动多个协程，并交给调度器驱动：

```lua
#!/usr/bin/env lua5.4

local time = require 'eco.time'
local eco = require 'eco'

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

eco.loop()
```

一个简单的 HTTPS 请求（写法仍然是同步的）：

```lua
#!/usr/bin/env lua5.4

local http = require 'eco.http.client'
local eco = require 'eco'

eco.run(function()
    local resp, err = http.get('https://example.com', { timeout = 10.0 })
    assert(resp, err)
    print('status:', resp.code)
    print(resp.body)
end)

eco.loop()
```

## 工作原理（简述）

- 所有 socket/file fd 都以 non-blocking 模式工作。
- 当协程执行 I/O 遇到 `EAGAIN`（暂不可读/写）时，会把 fd 注册到 `epoll` 并 `yield`。
- 主循环等待 I/O 就绪和定时器到点后自动 `resume` 对应协程。

因此，只要使用 lua-eco 的模块，I/O 都天然具备“自动协程调度”的并发模型。

## 模块一览

核心能力：

- `eco`：调度器与基础原语（`run/loop/sleep/io/reader/writer/...`）
- `time`：时间与定时器
- `log`：日志
- `sys`：信号、进程与执行/spawn 辅助
- `file`：文件系统辅助 + inotify
- `bufio`：buffered reader（更方便的读取接口）
- `sync`：协程间同步互斥（cond/mutex/...）
- `channel`：协程间通信 channel

网络相关：

- `socket`：TCP/UDP/UNIX/ICMP/raw/packet
- `ssl`：TLS client/server（后端支持 OpenSSL/WolfSSL/MbedTLS）
- `http`：HTTP client/server（`eco.http.client` / `eco.http.server` / `eco.http.url`）
- `websocket`：WebSocket client/server
- `mqtt`：MQTT 3.1.1 客户端实现
- `dns`：UDP DNS 解析

Linux / 系统集成：

- `packet`：低层报文构造与解析工具
- `nl` / `genl` / `rtnl` / `nl80211`：netlink 与无线（nl80211）
- `termios`：终端/串口 I/O
- `ip`, `net`：基于 netlink/socket 的网络工具集
- `shared`：基于 Unix Domain Socket 的本地共享字典（便于多进程间共享小数据）

OpenWrt：

- `ubus`：对 OpenWrt [ubus] 的封装（可选）
- `uci`：UCI 配置绑定（可选）

哈希/编码：

- `eco.hash`：`md5` / `sha1` / `sha256` / `hmac`
- `eco.encoding`：`base64` / `hex`

## 依赖

- Linux（调度器基于 `epoll`）
- Lua 5.4 开发头文件（`lua.h`）

可选依赖（自动探测，缺少则跳过对应模块）：

- TLS：OpenSSL / WolfSSL / MbedTLS（三选一即可）
- `ubus`：libubus + libubox（以及 json-c）
- `uci`：libuci
- `ssh`：libssh2

## 编译

### Ubuntu

    sudo apt install -y liblua5.4-dev
    git clone --recursive https://github.com/zhaojh329/lua-eco.git
    cd lua-eco && mkdir build && cd build
    cmake .. && sudo make install

如果你需要 OpenSSL TLS 支持：

    sudo apt install -y libssl-dev

如果不需要某些可选模块，可以关闭：

    cmake .. -DECO_SSL_SUPPORT=OFF -DECO_UBUS_SUPPORT=OFF -DECO_UCI_SUPPORT=OFF -DECO_SSH_SUPPORT=OFF

### OpenWrt

    Languages  --->
        Lua  --->
            -*- lua-eco............... A Lua interpreter with a built-in event loop
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
            <*> lua-eco-packet................................. packet support for lua-eco

## 文档与示例

- 直接打开生成的 API 文档：[doc/index.html](/doc/index.html)
- 参考可运行示例：[examples](/examples)
- 参考测试脚本：[tests](/tests)

## ❤️ [捐赠](https://zhaojh329.github.io/zhaojh329/)
