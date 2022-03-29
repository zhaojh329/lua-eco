* [eco](#eco): 核心模块
* [log](#log): 日志模块
* [time](#time): 时间模块
* [sys](#sys): 操作系统相关操作
* [file](#file): 文件相关操作
* [dns](#dns): DNS 解析
* [socket](#socket): 套接字
* [ssl](#ssl): SSL 操作
* [ubus](#ubus): OpenWrt 中的 UBUS
* [ip](#ip): 修改/维护网络接口
* [iw](#iw): 修改/维护无线设备

# eco
`eco.run(f, [, val1, ···])`

创建一个主体函数为 f 的新协程。 f 必须是一个 Lua 的函数。val1, ... 这些值会以参数形式传入主体函数

`eco.loop()`

调度协程运行

`eco.unloop()`

退出协程调度

`eco.VERSION_MAJOR`
`eco.VERSION_MINOR`
`eco.VERSION_PATCH`
`eco.VERSION_MAJOR`
`eco.VERSION`

几个表示当前版本的常量

`eco.count()`

获取当前运行中的协程个数

# log
当程序以守护进程运行时，日志输出到 `syslog`，否则输出到标准输出

`log.level(level)`

设置日志阈值: `log.EMERG` `log.ALERT` `log.CRIT` `log.ERR` `log.WARNING` `log.NOTICE` `log.INFO` `log.DEBUG`
默认为 `INFO`

`log.log(level, arg1, ...)`

以指定级别打印日志

`log.debug(arg1, ...)`
`log.info(arg1, ...)`
`log.err(arg1, ...)`

```lua
log.level(log.ERR)
log.log(log.ERR, "hello", "eco", 1, 2, 3, "ok")
log.err("hello", "eco", 1, 2, 3, "ok")
```

```bash
zjh@linux:~/work/lua-eco/build$ lua5.3 ../test.lua
2022/04/10 20:58:43 err lua5.3[177423]: (../test.lua:7) hello eco 1 2 3 ok
2022/04/10 20:58:43 err lua5.3[177423]: (../test.lua:8) hello eco 1 2 3 ok
```

# time

`time.sleep(delay)`

睡眠, 单位为秒

```lua
time.sleep(1.2)
```

`time.now()`

获取当前时间

# sys

`sys.getpid()`

获取当前进程的ID

`sys.getppid()`

获取当前进程的父进程的ID

`sys.exec(cmd, [arg1, arg2,...])`

执行命令，返回一个 userdata，支持如下方法：
* `settimeout(type, timeout)`: 设置超时时间，单位秒。 参数 type: "r"表示读取超时; "w"表示等待超时
* `stdout_read`: 从标准输出读取
* `stderr_read`: 从标准错误输出读取
* `wait`: 等待进程退出, 返回一个整数，表示进程退出状态码
* `kill`: 杀死进程

```lua
eco.run(
    function()
        local p = sys.exec("date", "-u")
        print(p:stdout_read())
        print(p:wait())
    end
)

eco.loop()
```

# file

`access(file, m)`

检测一个文件的权限, 返回一个 bool 值。如果 `m` 为 nil 则表示检查文件是否存在. m 支持多个字符的组合:
* `x`: 检测文件是否可执行
* `r`: 检测文件是否可读
* `w`: 检测文件是否可写

`readlink(file)`

获取一个符号链接的值

`stat(file)`

获取一个文件的信息，支持如下字段:

* `type`: "BLK", "CHR", "DIR", "FIFO", "LNK", "REG", "SOCK"
* `atime`:
* `mtime`:
* `ctime`:
* `nlink`:
* `uid`:
* `gid`:
* `size`:

`statvfs(file)`

获取文件系统信息，返回3个值(Byte): total, available, used.

```lua
local total, available, used = file.statvfs("/")
```

`dir(path)`

遍历文件夹

```lua
for name, info in file.dir("/") do
    print(name, info.type, info.size)
end
```

其中 `info` 包括的字段同上面介绍的 `stat` 方法

# dns

`dns.resolver(options)`

创建一个域名解析器

options 为一个可选的 Table，支持如下字段:
* `nameserver`: 域名服务器地址，如未提供，则从系统配置文件 `/etc/resolv.conf` 中查找
* `timeout`: 超时时间，单位秒，默认值为 3.0

`res:query(name)`

解析一个域名。以 Table 的形式返回该域名的所有 IP 地址，包括 IPv6 地址

```lua
local res = dns.resolver()
local address = res:query("www.google.com")
```

# socket

`socket.tcp(protocol)`

创建一个 TCP IPv4 套接字

`socket.tcp6(protocol)`

创建一个 TCP IPv6 套接字

`socket.udp(protocol)`

创建一个 UDP IPv4 套接字

`socket.udp6(protocol)`

创建一个 UDP IPv6 套接字

`socket.unix(protocol)`

创建一个 unix 套接字

`socket.unix_dgram(protocol)`

创建一个 unix 数据报套接字

`s:settimeout(type, timeout)`

设置超时时间，单位秒，其中 type 的可选值为:
* `"c"`: 设置连接超时时间
* `"r"`: 设置数据接收超时时间

`s:bind(ip, port)`

绑定一个 TCP 或者 UDP 套接字

`s:bind(path)`

绑定一个 unix 套接字

```lua
local s = socket.tcp()
local ok, err = s:bind(nil, 8080)
if not ok then
    print("bind fail:", err)
end
```

`s:listen()`

监听

`s:connect(ip, port)`
`s:connect(path)`

连接

```lua
local s = socket.tcp()
local ok, err = s:connect("192.168.1.1", 8080)
if not ok then
    print("connect fail:", err)
end
```

`s:accept()`

等待客户端的连接，返回一个代表客户端的新套接字

```lua
eco.run(
    function()
        local s = socket.tcp()
        s:bind(nil, 8080)
        s:listen()

        while true do
            local c = s:accept()
            eco.run(
                function()
                    while true do
                        local data, err = c:recv()
                        if not data then
                            print("recv fail:", err)
                            break
                        end
                        c:send(data)
                    end
                end
            )
        end
    end
)
```

`s:recv(...)`

接收数据,支持如下格式:
* "l": 读取一行并忽略行结束标记
* "L": 读取一行并保留行结束标记（如果有的话）
* number: 读取一个不超过这个数量字节数的字符串

`s:recvfrom()`

```lua
data, addr = s:recvfrom()
```

`s:send(data)`
`s:sendto(data, ip, port)`

发送数据

`s:getsockname()`

获取该套接字的本地地址信息。以 Table 的形式返回，包括如下字段:
* `family`: 地址类型: "inet", "inet6", "unix", "netlink"
* `ipaddr`: 针对 TCP 和 UDP 套接字
* `port`: 针对 TCP 和 UDP 套接字
* `path`: 针对 unix 套接字

`s:getpeername()`

获取已连接客户端的远端地址信息

`s:getfd()`

获取套接字描述符

`s:close()`

关闭套接字

`s:setoption(option, value)`

设置套接字选项. Option是一个带有选项名称的字符串，其值取决于所设置的选项:

* `keepalive`: boolean
* `linger`: a table with fields `on` and `timeout`
* `reuseaddr`: boolean
* `tcp-nodelay`: boolean
* `tcp-keepidle`: integer
* `tcp-keepcnt`: integer
* `tcp-keepintvl`: integer
* `ipv6-v6only`: boolean
* `dontroute`: boolean
* `broadcast`: boolean
* `ip-multicast-loop`: boolean
* `ip-multicast-if`: string
* `ip-multicast-ttl`: integer
* `ip-add-membership`: a table with fields multiaddr and interface, each containing an IP address
* `ip-drop-membership`: a table with fields multiaddr and interface, each containing an IP address.
* `recv-buffer-size`: integer
* `send-buffer-size`: integer

如果成功，该方法将返回 `true`，否则返回 `false`，并在后面跟着一条错误消息.

有关套接字选项的描述，请参阅手册页的 `socket(7)`

# ssl

`ssl.context(is_server)`

创建一个 ssl 上下文对象。可选参数 `is_server` 为 `bool` 类型，默认为 false

`ctx:load_ca_crt_file(file)`

`ctx:load_crt_file(file)`

`ctx:load_key_file(file)`

`ctx:set_ciphers(ciphers)`

`ctx:require_validation(true)`

`ctx:new(fd, insecure)`

创建一个 ssl 会话对象。可选参数 `insecure` 为 bool 类型，是否允许不安全的连接。默认为 false

`ssl_session:settimeout(timeout)`

设置读取超时时间，单位秒

`ssl_session:read(...)`

读数据,支持如下格式:
* "l": 读取一行并忽略行结束标记
* "L": 读取一行并保留行结束标记（如果有的话）
* number: 读取一个不超过这个数量字节数的字符串

`ssl_session:write(data)`

写数据

```lua
local ssl_ctx = ssl.context(true)
ssl_ctx:load_crt_file("cert.pem")
ssl_ctx:load_key_file("key.pem")

eco.run(
    function()
        local s = socket.tcp()
        s:bind(nil, 8080)
        s:listen()

        while true do
            local c = s:accept()

            local ssl_session = ssl_ctx:new(c:getfd(), true)

            eco.run(
                function()
                    while true do
                        local data = ssl_session:read()
                        if not data then break end
                        ssl_session:write(data)
                    end
                end
            )
        end
    end
)
```

# ubus

# ip

`ip:link(...)`

设置/显示网络设备 link 信息

`ip:addr(...)`

维护/显示网络设备地址信息

`ip:wait(timeout)`

等待 `link` 事件

# iw

`iw:add_interface(phy, name, typ, options)`

添加一个无线接口。options 为一个可选的 Table，支持如下字段:
* `addr`
* `4addr`

`iw:del_interface(name)`

删除一个无线接口

`iw:info(ifname)`

查询所有接口信息或者指定的接口信息

`iw:wait(timeout, event, ...)`

等待事件

`iw:scan_trigger(ifname, options)`

使用给定的参数触发新的扫描

`iw:scan_dump(ifname)`

获取扫描结果

`iw:assoclist(ifname)`

获取关联列表

`iw:freqlist(phy)`

获取支持的频率列表及最大功率值

`iw:countrylist()`

获取国家列表
