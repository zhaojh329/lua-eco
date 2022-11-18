* [eco](#eco): Core module
* [log](#log): Log module
* [time](#time): Time module
* [sys](#sys): Operations related to the operating system
* [file](#file): File related operations
* [dns](#dns): DNS Reverse
* [socket](#socket): Socket
* [ssl](#ssl): SSL operations
* [ubus](#ubus): OpenWrt's UBUS
* [ip](#ip): show / manipulate network devices
* [iw](#iw): show / manipulate wireless devices and their configuration

# eco
`eco.run(f, [, val1, ···])`

Creates a new coroutine, with body f. f must be a function. The values val1, ... are passed as the arguments to the body function

`eco.loop()`

Scheduling coroutines to run

`eco.unloop()`

Exit coroutines scheduling

`eco.VERSION_MAJOR`
`eco.VERSION_MINOR`
`eco.VERSION_PATCH`
`eco.VERSION_MAJOR`
`eco.VERSION`

Several constants representing the current version

`eco.count()`

Gets the number of coroutines currently running

# log
Logs are output to `syslog` when the program is run as a `daemon`, otherwise to `standard output`

`log.level(threshold)`

Sets threshold level: `log.EMERG` `log.ALERT` `log.CRIT` `log.ERR` `log.WARNING` `log.NOTICE` `log.INFO` `log.DEBUG`.
Default is `INFO`

`log.log(level, arg1, ...)`

Prints logs with a specified level

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

Sleep in seconds

```lua
time.sleep(1.2)
```

`time.now()`

Get the current time

# sys

`sys.uptime()`

Gets The time how long the system has been running

`sys.getpid()`

Gets process identification

`sys.getppid()`

Gets the process ID of the parent of the calling process

`sys.exec(cmd, [arg1, arg2,...])`

Invokes a command with zero or more arguments, return a userdata which support the following methods:
* `settimeout(type, timeout)`: Sets the timeout in seconds. Parameter `type`: "r" indicates read timeout; "W" indicates wait timeout
* `stdout_read`: Reads from stdout
* `stderr_read`: Reads from stderr
* `wait`: Waiting for the process to exit, returns an integer indicating the process's exit status code  
* `kill`: Kills the process

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

Check user's permissions for a file, return a `bool` value. If `m` is `nil`, then check whether the file exists.
`m` supports the combination of multiple characters:
* `x`: Checks whether the file is executable
* `r`: Checks whether the file is readable
* `w`: Checks whether the file is writable

`readlink(file)`

read value of a symbolic link

`stat(file)`

Gets file status. The following fields are supported:
* `type`: "BLK", "CHR", "DIR", "FIFO", "LNK", "REG", "SOCK"
* `atime`:
* `mtime`:
* `ctime`:
* `nlink`:
* `uid`:
* `gid`:
* `size`:

`statvfs(file)`

Gets file system information, returning three values(Byte): total, available, used.

```lua
local total, available, used = file.statvfs("/")
```

`dir(path)`

Traverses the folder

```lua
for name, info in file.dir("/") do
    print(name, info.type, info.size)
end
```

The `info` contains the same fields as the `stat` method described above  

`chown(path, uid, gid)`

change file owner and group

If the `uid` or `gid` is nil, then that ID is not changed.

# dns

`dns.resolver(options)`

Creates a domain name resolver

Options is an optional Table that supports the following fields:
* `nameserver`: If the DNS server address is not provided, obtain it from the system configuration file `/etc/resolv.conf`
* `timeout`: Timeout in seconds. The default value is 3.0

`res:query(name)`

Resolves a domain name.  All IP addresses of the domain including IPv6 addresses are returned as Table

```lua
local res = dns.resolver()
local address = res:query("www.google.com")
```

# socket

`socket.tcp(protocol)`

Creates a TCP IPv4 socket

`socket.tcp6(protocol)`

Creates a TCP IPv6 socket

`socket.udp(protocol)`

Creates a UDP IPv4 socket

`socket.udp6(protocol)`

Creates a UDP IPv6 socket

`socket.unix(protocol)`

Creates a unix socket

`socket.unix_dgram(protocol)`

Creates a unix datagrams socket

`s:settimeout(type, timeout)`

Set the timeout in seconds. The optional value of type is:
* `"c"`: Set the connection timeout
* `"r"`: The timeout for receiving data

`s:bind(ip, port)`

Binds a TCP or UDP socket

`s:bind(path)`

Binds a unix socket

```lua
local s = socket.tcp()
local ok, err = s:bind(nil, 8080)
if not ok then
    print("bind fail:", err)
end
```

`s:listen()`

`s:connect(ip, port)`
`s:connect(path)`

```lua
local s = socket.tcp()
local ok, err = s:connect("192.168.1.1", 8080)
if not ok then
    print("connect fail:", err)
end
```

`s:accept()`

Waiting for the client to connect, returns a new socket representing the new client

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

receive data, support following format:
* "l": reads the next line skipping the end of line
* "L": reads the next line keeping the end-of-line character (if present)
* number: reads a string with up to this number of bytes

`s:recvfrom()`

```lua
data, addr = s:recvfrom()
```

`s:send(data)`
`s:sendto(data, ip, port)`

Sends data

`s:getsockname()`

Returns the local address information associated to the socket. The value is returned as a Table, including the following fields:
* `family`: Addrss type: "inet", "inet6", "unix"
* `ipaddr`: For TCP and UDP
* `port`: For TCP and UDP
* `path`: For unix socket

`s:getpeername()`

Returns information about the remote side of a connected client socket.

`s:getfd()`

Returns the socket descriptor

`s:close()`

Close socket

`s:setoption(option, value)`

Set options on socket. Option is a string with the option name, and value depends on the option being set:

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

The method returns `true` in case of success, or `false` followed by an error message otherwise.

For a description of the socket options see socket(7) from the man pages.

# ssl

`ssl.context(is_server)`

Creates an SSL context object. The optional parameter `is_server` is a `bool` value, default value is false

`ctx:load_ca_crt_file(file)`

`ctx:load_crt_file(file)`

`ctx:load_key_file(file)`

`ctx:set_ciphers(ciphers)`

`ctx:require_validation(true)`

`ctx:new(fd, insecure)`

Creates an SSL session object. The optional parameter `insecure` is of type bool. Whether insecure connections are allowed. The default is false

`ssl_session:settimeout(timeout)`

Set the read timeout in seconds

`ssl_session:read(...)`

read data, support following format:
* "l": reads the next line skipping the end of line
* "L": reads the next line keeping the end-of-line character (if present)
* number: reads a string with up to this number of bytes

`ssl_session:write(data)`

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

Set/show network devices info

`ip:addr(...)`

manipulate/show address info 

`ip:wait(timeout)`

Wait `link` event

# iw

`iw:add_interface(phy, name, typ, options)`

Add an interface. Options is an optional Table that supports the following fields:
* `addr`
* `4addr`

`iw:del_interface(name)`

Delete an interface

`iw:info(ifname)`

Get information of all interfaces or a specified interface.

`iw:wait(timeout, event, ...)`

Wait event.

`iw:scan_trigger(ifname, options)`

trigger a new scan with the given parameters

`iw:scan_dump(ifname)`

Get scan results.

`iw:assoclist(ifname)`

Get association list.

`iw:freqlist(phy)`

Get frequency list and tx power limit.

`iw:countrylist()`

Get country code list.
