# API Quick Reference (Generated)

Generated from lua-eco LDoc search data and merged with the public API manifest.
Official docs root: https://zhaojh329.github.io/lua-eco/

Do not edit by hand. Run `scripts/update-api-reference.sh`.

## eco
- `all` - all () [Functions]. Get a table of all currently tracked coroutines. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.html#all
- `count` - count () [Functions]. Get the number of currently tracked coroutines. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.html#count
- `eco.writer` - eco.writer [Manifest]. Listed in the public API manifest; no LDoc search entry is currently available. Docs: https://zhaojh329.github.io/lua-eco/
- `io` - io (fd) [Functions]. Create a new async I/O object wrapping a file descriptor. This function sets the given file descriptor to non-blocking mode and wraps it in an `eco.io` userdata object, allowing async I/O operations via `io:wait()` and `io:cancel()`. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.html#io
- `io:cancel` - io:cancel () [Class io]. Cancel a pending wait on this I/O object. If a coroutine is currently suspended in `io:wait()`, it will be resumed immediately and `io:wait()` will return nil, "canceled". Docs: https://zhaojh329.github.io/lua-eco/modules/eco.html#io:cancel
- `io:wait` - io:wait (ev[, timeout]) [Class io]. Wait for the underlying file descriptor to become ready. Suspends the current coroutine until the file descriptor is ready for reading (EPOLLIN) or writing (EPOLLOUT), or until an optional timeout. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.html#io:wait
- `loop` - loop () [Functions]. Run the event loop of the eco scheduler. This function drives the scheduler, processing timers, I/O events, and resuming coroutines as needed. `eco.loop()` returns when `eco.unloop()` is called, when interrupted by SIGINT, or when there are no monitorable events left (no pending I/O watchers and no scheduled timers). Docs: https://zhaojh329.github.io/lua-eco/modules/eco.html#loop
- `reader` - reader (fd[, read[, ctx]]) [Functions]. Create a new reader object. Wraps a file descriptor in an `eco.reader` object for async I/O. Optionally, a custom read function and context pointer can be provided. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.html#reader
- `reader:cancel` - reader:cancel () [Class reader]. Cancel a pending read operation. If a coroutine is currently suspended in `read`, `read2b` or `wait`, it will be resumed immediately and return nil with error "canceled". Docs: https://zhaojh329.github.io/lua-eco/modules/eco.html#reader:cancel
- `reader:read` - reader:read (format[, timeout]) [Class reader]. Reads data from the underlying file descriptor in the given format. The available formats are: - `"a"`: reads the whole file or reads from socket until the connection closed. - `"l"`: reads the next line skipping the end of line(The line is terminated by a Line Feed (LF) character (ASCII 10), optionally preceded by a Carriage Return (CR) character (ASCII 13). The CR and LF characters are not included in the returned line). - `"L"`: reads the next line keeping the end-of-line character. - `int`: reads a string with up to this number of bytes. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.html#reader:read
- `reader:readfull` - reader:readfull (size[, timeout]) [Class reader]. Reads exactly `size` bytes from the underlying file descriptor. This method will not return until it reads exactly this size of data or an error occurs. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.html#reader:readfull
- `reader:readuntil` - reader:readuntil (needle[, timeout]) [Class reader]. Read until the specified `needle` is found. This function can be called multiple times. It returns data as it arrives. When `needle` is seen, it returns the data preceding it and a boolean `true`. The `needle` itself is consumed and not included in returned data. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.html#reader:readuntil
- `reader:wait` - reader:wait ([timeout]) [Class reader]. Wait for the underlying file descriptor to become readable. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.html#reader:wait
- `resume` - resume [Manifest]. Listed in the public API manifest; no LDoc search entry is currently available. Docs: https://zhaojh329.github.io/lua-eco/
- `run` - run (func, ...) [Functions]. Run a Lua function in a new coroutine. This function creates a new Lua coroutine, moves the provided function and its arguments into it, and resumes the coroutine immediately. The coroutine is tracked internally by `eco`. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.html#run
- `set_panic_hook` - set_panic_hook ([func]) [Functions]. Set or clear the scheduler panic hook. The hook is called when an uncaught error occurs inside a coroutine managed by `eco`. The callback receives two traceback strings: 1. traceback from the currently running coroutine (the one that failed) 2. traceback from the coroutine/context that resumed it Pass `nil` to clear a previously installed hook. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.html#set_panic_hook
- `set_watchdog_timeout` - set_watchdog_timeout (ms) [Functions]. Set or clear coroutine resume watchdog timeout in milliseconds. If a single `resume` runs longer than this timeout, eco triggers panic and prints traceback via the existing panic path. The default timeout is 2000 milliseconds. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.html#set_watchdog_timeout
- `sleep` - sleep (delay) [Functions]. Suspend the current coroutine for a given delay. This function yields the current Lua coroutine and resumes it after `delay` seconds. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.html#sleep
- `unloop` - unloop () [Functions]. Stop the eco scheduler main loop. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.html#unloop
- `writer` - writer (fd[, write[, ctx]]) [Functions]. Create a new writer object. Wraps a file descriptor in an `eco.writer` object for asynchronous write operations. Optionally, a custom write function and context pointer can be provided. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.html#writer
- `writer:cancel` - writer:cancel () [Class writer]. Cancel a pending write operation. If a coroutine is currently suspended in `write`, `sendfile` or `wait`, it will be resumed immediately and return nil with error "canceled". Docs: https://zhaojh329.github.io/lua-eco/modules/eco.html#writer:cancel
- `writer:sendfile` - writer:sendfile (path, offset, len[, timeout]) [Class writer]. Send a file's content to the writer's file descriptor. Uses the `sendfile` system call to send `len` bytes starting from `offset` of the file at `path` to the writer's file descriptor. If the operation would block, the coroutine is suspended and resumed automatically when the descriptor is writable. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.html#writer:sendfile
- `writer:wait` - writer:wait ([timeout]) [Class writer]. Wait for the underlying file descriptor to become writable. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.html#writer:wait
- `writer:write` - writer:write (data[, timeout]) [Class writer]. Write data to the writer's file descriptor. Writes the given string `data` to the file descriptor wrapped by this `eco.writer`. If the write would block, the coroutine is suspended and resumed automatically when the descriptor is writable. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.html#writer:write

## eco.channel
- `channel:close` - channel:close () [Class channel]. Close the channel. This is idempotent. After closing, @{channel:recv} returns `nil` once the buffer is drained. @{channel:send} will raise an error. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.channel.html#channel:close
- `channel:length` - channel:length () [Class channel]. Get the number of buffered items. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.channel.html#channel:length
- `channel:recv` - channel:recv ([timeout]) [Class channel]. Receive a value from the channel. If the channel is closed and the buffer is empty, returns `nil`. On timeout, returns `nil, 'timeout'`. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.channel.html#channel:recv
- `channel:send` - channel:send (v[, timeout]) [Class channel]. Send a value to the channel. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.channel.html#channel:send
- `new` - new ([capacity=1]) [Functions]. Create a channel. If `capacity` is not provided or is less than 1, it defaults to 1. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.channel.html#new

## eco.cli
- `parse_args` - parse_args (spec[, argv]) [Functions]. Parse script command-line arguments. Options are described with Lua tables. Parsed values are returned in a result table keyed by option `name`; positional arguments are returned in `result.args`. If `argv` is omitted, the global `arg` table is used and `arg[0]` is ignored. Each option supports these fields: - `name` (required): result field name and default long option name - `short`: one-character short option - `long`: long option name; defaults to `name` - `type`: `"boolean"` (default), `"string"`, `"number"`, `"integer"`, `"count"` or `"array"` - `default`: default value - `required`: fai Docs: https://zhaojh329.github.io/lua-eco/modules/eco.cli.html#parse_args

## eco.dns
- `CLASS_IN` - CLASS_IN [Fields]. DNS class: IN (Internet). Docs: https://zhaojh329.github.io/lua-eco/modules/eco.dns.html#CLASS_IN
- `query` - query (qname[, opts]) [Functions]. Resolve a DNS name. The return value is an array of answer records. Record table fields depend on the record type. Common fields: - `name`, `type`, `class`, `ttl`, `section` Type-specific fields include: - `A/AAAA`: `address` - `CNAME`: `cname` - `MX`: `preference`, `exchange` - `SRV`: `priority`, `weight`, `port`, `target` - `NS`: `nsdname` - `TXT`: `txt` (string or array of strings) - `SPF`: `spf` (string or array of strings) - `PTR`: `ptrdname` - `SOA`: `mname`, `rname`, `serial`, `refresh`, `retry`, `expire`, `minimum` Docs: https://zhaojh329.github.io/lua-eco/modules/eco.dns.html#query
- `SECTION_AN` - SECTION_AN [Fields]. DNS answer section: Answer. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.dns.html#SECTION_AN
- `SECTION_AR` - SECTION_AR [Fields]. DNS answer section: Additional. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.dns.html#SECTION_AR
- `SECTION_NS` - SECTION_NS [Fields]. DNS answer section: Authority. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.dns.html#SECTION_NS
- `TYPE_A` - TYPE_A [Fields]. Resource record type: A. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.dns.html#TYPE_A
- `TYPE_AAAA` - TYPE_AAAA [Fields]. Resource record type: AAAA. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.dns.html#TYPE_AAAA
- `TYPE_CNAME` - TYPE_CNAME [Fields]. Resource record type: CNAME. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.dns.html#TYPE_CNAME
- `TYPE_MX` - TYPE_MX [Fields]. Resource record type: MX. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.dns.html#TYPE_MX
- `type_name` - type_name (n) [Functions]. Convert RR type number to its mnemonic. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.dns.html#type_name
- `TYPE_NS` - TYPE_NS [Fields]. Resource record type: NS. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.dns.html#TYPE_NS
- `TYPE_PTR` - TYPE_PTR [Fields]. Resource record type: PTR. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.dns.html#TYPE_PTR
- `TYPE_SOA` - TYPE_SOA [Fields]. Resource record type: SOA. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.dns.html#TYPE_SOA
- `TYPE_SPF` - TYPE_SPF [Fields]. Resource record type: SPF. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.dns.html#TYPE_SPF
- `TYPE_SRV` - TYPE_SRV [Fields]. Resource record type: SRV. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.dns.html#TYPE_SRV
- `TYPE_TXT` - TYPE_TXT [Fields]. Resource record type: TXT. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.dns.html#TYPE_TXT

## eco.encoding.base64
- `decode` - decode (data) [Functions]. Decode a Base64 string. On malformed input, returns `nil, "input is malformed"`. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.encoding.base64.html#decode
- `encode` - encode (data) [Functions]. Encode data to Base64. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.encoding.base64.html#encode

## eco.encoding.hex
- `decode` - decode (s) [Functions]. Decode a hexadecimal string into bytes. On malformed input, returns `nil, 'input is malformed'`. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.encoding.hex.html#decode
- `dump` - dump (data) [Functions]. Format a hexdump of the given data. The format matches the output of `hexdump -C`. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.encoding.hex.html#dump
- `encode` - encode (bin[, sep='']) [Functions]. Encode bytes to a hexadecimal string. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.encoding.hex.html#encode

## eco.file
- `access` - access (file[, mode]) [Functions]. Test file accessibility. Thin wrapper around POSIX `access(2)`. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.file.html#access
- `basename` - basename (path) [Functions]. Get last path component. Wrapper around `basename(3)`. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.file.html#basename
- `chown` - chown (pathname[, uid[, gid]]) [Functions]. Change owner and group of a file. Thin wrapper around POSIX `chown(2)`. To keep a value unchanged, pass `nil` for that argument. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.file.html#chown
- `dir` - dir (path) [Functions]. Iterate a directory. Convenience iterator around `opendir(3)` / `readdir(3)`. Each iteration returns entry name and a @{stat} style info table. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.file.html#dir
- `dirname` - dirname (path) [Functions]. Get directory part of a path. Wrapper around `dirname(3)`. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.file.html#dirname
- `file:close` - file:close () [Class file]. Close the file. This is idempotent and is also used as the `__gc` / `__close` metamethod. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.file.html#file:close
- `file:flock` - file:flock (fd, operation[, timeout]) [Class file]. Acquire or release an advisory file lock. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.file.html#file:flock
- `file:lseek` - file:lseek (offset, where) [Class file]. Reposition read/write file offset. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.file.html#file:lseek
- `file:read` - file:read () [Class file]. See @{eco.reader:read} Docs: https://zhaojh329.github.io/lua-eco/modules/eco.file.html#file:read
- `file:readfull` - file:readfull () [Class file]. See @{eco.reader:readfull} Docs: https://zhaojh329.github.io/lua-eco/modules/eco.file.html#file:readfull
- `file:readuntil` - file:readuntil () [Class file]. See @{eco.reader:readuntil} Docs: https://zhaojh329.github.io/lua-eco/modules/eco.file.html#file:readuntil
- `file:stat` - file:stat () [Class file]. Get file status. Thin wrapper around POSIX `fstat(2)`. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.file.html#file:stat
- `file:write` - file:write () [Class file]. See @{eco.writer:write} Docs: https://zhaojh329.github.io/lua-eco/modules/eco.file.html#file:write
- `flock` - flock [Manifest]. Listed in the public API manifest; no LDoc search entry is currently available. Docs: https://zhaojh329.github.io/lua-eco/
- `fstat` - fstat [Manifest]. Listed in the public API manifest; no LDoc search entry is currently available. Docs: https://zhaojh329.github.io/lua-eco/
- `inotify` - inotify () [Functions]. Create an inotify watcher. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.file.html#inotify
- `inotify:add` - inotify:add (path[, mask]) [Class inotify]. Add a path to be watched. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.file.html#inotify:add
- `inotify:close` - inotify:close () [Class inotify]. Close the watcher. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.file.html#inotify:close
- `inotify:del` - inotify:del (wd) [Class inotify]. Remove a watch by its watch descriptor. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.file.html#inotify:del
- `inotify:wait` - inotify:wait ([timeout]) [Class inotify]. Wait for an inotify event. If there are already parsed events buffered in the watcher, returns the next one immediately; otherwise, reads from the underlying inotify fd. The returned event is a table with fields: - `name`: full path of the affected entry - `mask`: inotify mask bits (`file.IN_ACCESS`, `file.IN_MODIFY`, `file.IN_OPEN`,...) Docs: https://zhaojh329.github.io/lua-eco/modules/eco.file.html#inotify:wait
- `mkdir` - mkdir (pathname[, mode=0777]) [Functions]. Create a directory. Calls the underlying POSIX `mkdir(2)` function. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.file.html#mkdir
- `open` - open (path[, flags=file.O_RDONLY[, mode=0]]) [Functions]. Open and possibly create a file Docs: https://zhaojh329.github.io/lua-eco/modules/eco.file.html#open
- `readfile` - readfile (path[, m='*a']) [Functions]. Read contents from a file. Opens the file in read-only mode and reads data using `file:read`. The file handle is automatically closed after use. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.file.html#readfile
- `readlink` - readlink (path) [Functions]. Read value of a symbolic link. Thin wrapper around POSIX `readlink(2)`. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.file.html#readlink
- `SKIP` - SKIP [Fields]. Special return value for @{walk} callback to skip descending into the current directory. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.file.html#SKIP
- `stat` - stat (path) [Functions]. Get file status by path. Thin wrapper around POSIX `stat(2)`. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.file.html#stat
- `statvfs` - statvfs (path) [Functions]. Get filesystem statistics. Thin wrapper around `statvfs(3)`. The returned values are in KiB (kibibytes). Docs: https://zhaojh329.github.io/lua-eco/modules/eco.file.html#statvfs
- `sync` - sync () [Functions]. Commit filesystem caches to disk Calls the underlying POSIX `sync(2)` function. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.file.html#sync
- `walk` - walk (root, cb) [Functions]. Recursively traverse a directory tree. For each entry under `root`, invokes `cb(fullpath, name, info)`. `info` is the same table returned by @{dir}. Callback return values: - `false`: terminate traversal - @{file.SKIP}: if the current entry is a directory, do not descend into it - anything else / nil: continue Docs: https://zhaojh329.github.io/lua-eco/modules/eco.file.html#walk
- `writefile` - writefile (path, data[, append=false]) [Functions]. Write data to a file. Opens the file in write mode (`'w'`) by default, or append mode (`'a'`) when `append` is true. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.file.html#writefile

## eco.genl
- `family` - family [Tables]. Generic netlink family info. Returned by @{get_family_byid} and @{get_family_byname}. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.genl.html#family
- `genlmsghdr` - genlmsghdr (t) [Functions]. Build a `struct genlmsghdr`. Returns a binary string containing the packed C structure. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.genl.html#genlmsghdr
- `get_family_byid` - get_family_byid (id) [Functions]. Query Generic Netlink family info by numeric id. Results are cached in-process. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.genl.html#get_family_byid
- `get_family_byname` - get_family_byname (name) [Functions]. Query Generic Netlink family info by family name. Results are cached in-process. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.genl.html#get_family_byname
- `get_family_id` - get_family_id (name) [Functions]. Get numeric family id by family name. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.genl.html#get_family_id
- `get_group_id` - get_group_id (family, group) [Functions]. Get multicast group id for a family/group name pair. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.genl.html#get_group_id
- `parse_genlmsghdr` - parse_genlmsghdr (msg) [Functions]. Parse a `struct genlmsghdr` from a netlink message parser. The parser must currently point at a Generic Netlink message (i.e. a netlink message with `nlmsg_type >= NLMSG_MIN_TYPE`). Docs: https://zhaojh329.github.io/lua-eco/modules/eco.genl.html#parse_genlmsghdr

## eco.hash.hmac
- `hmac:final` - hmac:final () [Class hmac]. Finalize and return the HMAC digest. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.hash.hmac.html#hmac:final
- `hmac:update` - hmac:update (data) [Class hmac]. Update HMAC with more data. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.hash.hmac.html#hmac:update
- `new` - new (hash, key) [Functions]. Create a new HMAC context. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.hash.hmac.html#new
- `sum` - sum (hash, key, data) [Functions]. One-shot HMAC. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.hash.hmac.html#sum

## eco.hash.md5
- `md5:final` - md5:final () [Class md5]. Finalize and return digest. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.hash.md5.html#md5:final
- `md5:update` - md5:update (data) [Class md5]. Update digest with more data. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.hash.md5.html#md5:update
- `new` - new () [Functions]. Create a new incremental MD5 context. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.hash.md5.html#new
- `sum` - sum (data) [Functions]. Compute MD5 digest of the given data. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.hash.md5.html#sum

## eco.hash.sha1
- `new` - new () [Functions]. Create a new incremental SHA1 context. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.hash.sha1.html#new
- `sha1:final` - sha1:final () [Class sha1]. Finalize and return digest. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.hash.sha1.html#sha1:final
- `sha1:update` - sha1:update (data) [Class sha1]. Update digest with more data. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.hash.sha1.html#sha1:update
- `sum` - sum (data) [Functions]. Compute SHA1 digest of the given data. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.hash.sha1.html#sum

## eco.hash.sha256
- `new` - new () [Functions]. Create a new incremental SHA256 context. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.hash.sha256.html#new
- `sha256:final` - sha256:final () [Class sha256]. Finalize and return digest. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.hash.sha256.html#sha256:final
- `sha256:update` - sha256:update (data) [Class sha256]. Update digest with more data. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.hash.sha256.html#sha256:update
- `sum` - sum (data) [Functions]. Compute SHA256 digest of the given data. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.hash.sha256.html#sum

## eco.http.client
- `body_form:add` - body_form:add (name, value) [Class body_form]. Add a simple form field. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.http.client.html#body_form:add
- `body_form:add_file` - body_form:add_file (name, path) [Class body_form]. Add a file field. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.http.client.html#body_form:add_file
- `body_with_file` - body_with_file (name) [Functions]. Use a file as request body. The returned object can be used as the `body` argument of @{request}. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.http.client.html#body_with_file
- `client:close` - client:close () [Class client]. Close the underlying connection. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.http.client.html#client:close
- `client:request` - client:request (method, url[, body[, opts]]) [Class client]. Perform a request using this client. For `https`/`wss`, TLS options in `opts` are passed to @{eco.ssl.connect}. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.http.client.html#client:request
- `client:sock` - client:sock () [Class client]. Get the underlying connected socket. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.http.client.html#client:sock
- `form` - form () [Functions]. Create a multipart form body. The returned object can be used as the `body` argument of @{request}. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.http.client.html#form
- `get` - get (url[, opts]) [Functions]. Convenience wrapper for `GET`. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.http.client.html#get
- `new` - new () [Functions]. Create a new HTTP client. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.http.client.html#new
- `post` - post (url[, body[, opts]]) [Functions]. Convenience wrapper for `POST`. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.http.client.html#post
- `request` - request (method, url[, body[, opts]]) [Functions]. Perform an HTTP request. This is a convenience wrapper that creates a temporary client, performs the request, and closes the connection. `opts` options commonly used: - `timeout` (number) request timeout in seconds (default 30). - `headers` (table) extra request headers. - `body_to_file` (string) write response body to the given file path. - `ipv6` (boolean) resolve AAAA records. - `mark` (number) SO_MARK for sockets. - `device` (string) SO_BINDTODEVICE for sockets. - `nameservers` (table) DNS servers (see @{eco.dns.query}). - TLS: `ca`, `cert`, `key`, `insecure` (passed to @{eco.ssl.connect}) Docs: https://zhaojh329.github.io/lua-eco/modules/eco.http.client.html#request

## eco.http.server
- `connection:add_header` - connection:add_header (name, value) [Class connection]. Add/override a response header. Must be called before the response head is sent. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.http.server.html#connection:add_header
- `connection:discard_body` - connection:discard_body () [Class connection]. Discard remaining request body bytes. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.http.server.html#connection:discard_body
- `connection:flush` - connection:flush () [Class connection]. Flush pending response data. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.http.server.html#connection:flush
- `connection:read_body` - connection:read_body ([count[, timeout]]) [Class connection]. Read request body data. Reads up to `count` bytes from the request body. Returns an empty string when the body is fully consumed. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.http.server.html#connection:read_body
- `connection:read_formdata` - connection:read_formdata (req[, timeout]) [Class connection]. Incrementally parse multipart/form-data. This helper parses multipart formdata from the request body and returns events: - `"header"`, `{ name, value }` - `"body"`, `{ data, done }` where `done` indicates end of part - `"end"` when finished Docs: https://zhaojh329.github.io/lua-eco/modules/eco.http.server.html#connection:read_formdata
- `connection:redirect` - connection:redirect (code, location) [Class connection]. Redirect to another location. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.http.server.html#connection:redirect
- `connection:remote_addr` - connection:remote_addr () [Class connection]. Get peer address. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.http.server.html#connection:remote_addr
- `connection:send` - connection:send [Manifest]. Listed in the public API manifest; no LDoc search entry is currently available. Docs: https://zhaojh329.github.io/lua-eco/
- `connection:send_error` - connection:send_error (code[, status[, content]]) [Class connection]. Send an error response. If `content` is omitted, sends an empty body. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.http.server.html#connection:send_error
- `connection:send_file` - connection:send_file (path[, count[, offset]]) [Class connection]. Send a file as chunked response body. This is a helper for serving static files and uses chunked encoding. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.http.server.html#connection:send_file
- `connection:serve_file` - connection:serve_file (req) [Class connection]. Serve a static file from `options.docroot`. This helper implements basic file serving with `etag` and `if-modified-since` handling. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.http.server.html#connection:serve_file
- `connection:set_status` - connection:set_status (code[, status]) [Class connection]. Set response status code. Must be called before the response head is sent. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.http.server.html#connection:set_status
- `listen` - listen ([ipaddr], port[, options], handler) [Functions]. Listen and serve HTTP requests. This function creates a listening socket and enters an accept loop. The `handler` is called as `handler(con, req)` for each request. Returning `false` from the handler closes the connection. `req` is a plain table with common fields: - `method`, `raw_path`, `path` - `major_version`, `minor_version` - `headers` (lowercased keys) - `query` (table) and `query_string` - `form` (table) used by @{connection:read_formdata} `options` commonly used: - `docroot` (string) document root (default `.`). - `index` (string) index file name (default `index.html`). - `http_keepal Docs: https://zhaojh329.github.io/lua-eco/modules/eco.http.server.html#listen

## eco.http.url
- `escape` - escape [Manifest]. Listed in the public API manifest; no LDoc search entry is currently available. Docs: https://zhaojh329.github.io/lua-eco/
- `parse` - parse [Manifest]. Listed in the public API manifest; no LDoc search entry is currently available. Docs: https://zhaojh329.github.io/lua-eco/
- `unescape` - unescape [Manifest]. Listed in the public API manifest; no LDoc search entry is currently available. Docs: https://zhaojh329.github.io/lua-eco/

## eco.ip
- `address.add` - address.add (dev, addr) [Functions]. Add an IPv4 address to an interface. `addr.address` may include prefix length in CIDR form (e.g. `"192.168.1.2/24"`). Supported `addr` fields: - `address` (string): IPv4 address (optionally with `/prefix`) - `prefix` (number): prefix length (default: 32) - `scope` (string): one of `"global"`, `"nowhere"`, `"host"`, `"link"`, `"site"` - `broadcast` (string): IPv4 broadcast address - `label` (string) - `metric` (number) - `priority` (number) Note: this helper currently builds an IPv4 (`AF_INET`) request. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.ip.html#address.add
- `address.del` - address.del (dev, addr) [Functions]. Delete an IPv4 address from an interface. Uses the same `addr` format as @{address.add}. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.ip.html#address.del
- `address.get` - address.get ([dev]) [Functions]. Get addresses. When `dev` is omitted, dumps addresses for all interfaces. Returns an array of tables with fields: - `ifname` (string) - `family` (int): address family (e.g. @{eco.socket.AF_INET}) - `scope` (string): scope name - `address` (string) - `broadcast` (string|nil) (IPv4 only) - `label` (string|nil) Docs: https://zhaojh329.github.io/lua-eco/modules/eco.ip.html#address.get
- `link.get` - link.get (dev) [Functions]. Get link attributes. Returns a table with fields: - `ifname` (string) - `alias` (string) - `master` (string) - `type` (int) - `mtu` (int) - `txqueuelen` (int) - `address` (string): MAC as `"xx:xx:..."` - `broadcast` (string): MAC as `"xx:xx:..."` - `carrier` (boolean) - flags (boolean): `up`, `running`, `arp`, `dynamic`, `multicast`, `allmulticast`, `promisc` Docs: https://zhaojh329.github.io/lua-eco/modules/eco.ip.html#link.get
- `link.set` - link.set (dev[, attrs]) [Functions]. Set link attributes. Supported `attrs` fields: - `up` (boolean): bring interface up - `down` (boolean): bring interface down - `arp` (boolean): enable/disable ARP - `dynamic` (boolean) - `multicast` (boolean) - `allmulticast` (boolean) - `promisc` (boolean) - `carrier` (boolean) - `txqueuelen` (number) - `address` (string): MAC address like `"00:11:22:33:44:55"` - `broadcast` (string): MAC address - `mtu` (number) - `alias` (string) - `master` (string): master interface name - `nomaster` (boolean): detach from master Docs: https://zhaojh329.github.io/lua-eco/modules/eco.ip.html#link.set

## eco.log
- `debug` - debug ([...]) [Functions]. Log a DEBUG message. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.log.html#debug
- `err` - err ([...]) [Functions]. Log an ERR message. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.log.html#err
- `info` - info ([...]) [Functions]. Log an INFO message. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.log.html#info
- `log` - log (priority[, ...]) [Functions]. Log a message at a specific priority. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.log.html#log
- `set_flags` - set_flags (flags) [Functions]. Set log flags. Combine flags using bitwise OR, e.g. `log.FLAG_LF | log.FLAG_FILE`. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.log.html#set_flags
- `set_ident` - set_ident (ident) [Functions]. Set syslog/file ident. This also affects the prefix when logging to file/stdout. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.log.html#set_ident
- `set_level` - set_level (level) [Functions]. Set current log level. Messages with priority greater than `level` are discarded. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.log.html#set_level
- `set_path` - set_path (path) [Functions]. Set log output file path. When set to a non-empty path, logs are appended to that file. Passing an empty string resets output back to stdout/syslog. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.log.html#set_path
- `set_roll_count` - set_roll_count (count) [Functions]. Set max number of rolled files to keep. Values less than or equal to 0 are treated as library default. Default is `10`. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.log.html#set_roll_count
- `set_roll_size` - set_roll_size (size) [Functions]. Set log roll size threshold in bytes. When current log file size reaches this threshold, it is rotated. `0` disables log rolling. Default is `100 * 1024` bytes. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.log.html#set_roll_size

## eco.mqtt
- `client:close` - client:close () [Class client]. Close the underlying network socket. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.mqtt.html#methods:close
- `client:disconnect` - client:disconnect () [Class client]. Send DISCONNECT. This only sends the packet; the underlying socket is not closed here. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.mqtt.html#methods:disconnect
- `client:on` - client:on (event, handler, handlers) [Class client]. Register event handler(s). This function supports two calling forms: - `client:on(event, handler)` - `client:on({ event1 = handler1, event2 = handler2 })` The handler is called as `handler(data, client)`. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.mqtt.html#methods:on
- `client:publish` - client:publish (topic, payload[, qos=mqtt.QOS0[, retain]]) [Class client]. Publish a message. For QoS 1 and 2, the client will keep the packet for retransmission until an acknowledgement is received. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.mqtt.html#methods:publish
- `client:run` - client:run () [Class client]. Connect and start handling packets. This call returns when the network connection is closed or an error occurs. Any termination reason is reported through the `error` event. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.mqtt.html#methods:run
- `client:set` - client:set (name, value) [Class client]. Set one option on the client. This is equivalent to providing the field in @{new}'s `opts`. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.mqtt.html#methods:set
- `client:subscribe` - client:subscribe (topic[, qos=mqtt.QOS0], ...) [Class client]. Subscribe to topic(s). This sends a SUBSCRIBE packet and later triggers the `suback` event. Arguments are accepted as `(topic, qos, topic2, qos2, ...)`, and must be in pairs. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.mqtt.html#methods:subscribe
- `client:unsubscribe` - client:unsubscribe (topic, ...) [Class client]. Unsubscribe from topic(s). This sends an UNSUBSCRIBE packet and later triggers the `unsuback` event. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.mqtt.html#methods:unsubscribe
- `CONNACK_ACCEPTED` - CONNACK_ACCEPTED [Fields]. CONNACK return code: connection accepted. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.mqtt.html#CONNACK_ACCEPTED
- `CONNACK_REFUSED_BAD_USER_NAME_OR_PASSWORD` - CONNACK_REFUSED_BAD_USER_NAME_OR_PASSWORD [Fields]. CONNACK return code: bad username or password. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.mqtt.html#CONNACK_REFUSED_BAD_USER_NAME_OR_PASSWORD
- `CONNACK_REFUSED_IDENTIFIER_REJECTED` - CONNACK_REFUSED_IDENTIFIER_REJECTED [Fields]. CONNACK return code: identifier rejected. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.mqtt.html#CONNACK_REFUSED_IDENTIFIER_REJECTED
- `CONNACK_REFUSED_NOT_AUTHORIZED` - CONNACK_REFUSED_NOT_AUTHORIZED [Fields]. CONNACK return code: not authorized. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.mqtt.html#CONNACK_REFUSED_NOT_AUTHORIZED
- `CONNACK_REFUSED_PROTOCOL_VERSION` - CONNACK_REFUSED_PROTOCOL_VERSION [Fields]. CONNACK return code: unacceptable protocol version. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.mqtt.html#CONNACK_REFUSED_PROTOCOL_VERSION
- `CONNACK_REFUSED_SERVER_UNAVAILABLE` - CONNACK_REFUSED_SERVER_UNAVAILABLE [Fields]. CONNACK return code: server unavailable. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.mqtt.html#CONNACK_REFUSED_SERVER_UNAVAILABLE
- `new` - new ([opts]) [Functions]. Create a new MQTT client. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.mqtt.html#new
- `QOS0` - QOS0 [Fields]. QoS 0: at most once. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.mqtt.html#QOS0
- `QOS1` - QOS1 [Fields]. QoS 1: at least once. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.mqtt.html#QOS1
- `QOS2` - QOS2 [Fields]. QoS 2: exactly once. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.mqtt.html#QOS2
- `SUBACK_FAILURE` - SUBACK_FAILURE [Fields]. SUBACK failure return code. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.mqtt.html#SUBACK_FAILURE

## eco.net
- `ping` - ping (host[, opts]) [Functions]. Send an ICMP echo request (IPv4). If `host` is a domain name, it will be resolved using DNS A records. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.net.html#ping
- `ping6` - ping6 (host[, opts]) [Functions]. Send an ICMP echo request (IPv6). If `host` is a domain name, it will be resolved using DNS AAAA records. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.net.html#ping6
- `PingOptions` - PingOptions [Tables]. Options table for @{net.ping} / @{net.ping6}. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.net.html#PingOptions

## eco.nl
- `attr_get_payload` - attr_get_payload (attr) [Functions]. Get the raw payload bytes of an attribute. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.nl.html#attr_get_payload
- `attr_get_s16` - attr_get_s16 (attr) [Functions]. Decode an attribute whose payload is a signed 16-bit integer. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.nl.html#attr_get_s16
- `attr_get_s32` - attr_get_s32 (attr) [Functions]. Decode an attribute whose payload is a signed 32-bit integer. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.nl.html#attr_get_s32
- `attr_get_s64` - attr_get_s64 (attr) [Functions]. Decode an attribute whose payload is a signed 64-bit integer. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.nl.html#attr_get_s64
- `attr_get_s8` - attr_get_s8 (attr) [Functions]. Decode an attribute whose payload is a signed 8-bit integer. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.nl.html#attr_get_s8
- `attr_get_str` - attr_get_str (attr) [Functions]. Decode an attribute whose payload is a NUL-terminated string. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.nl.html#attr_get_str
- `attr_get_u16` - attr_get_u16 (attr) [Functions]. Decode an attribute whose payload is an unsigned 16-bit integer. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.nl.html#attr_get_u16
- `attr_get_u32` - attr_get_u32 (attr) [Functions]. Decode an attribute whose payload is an unsigned 32-bit integer. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.nl.html#attr_get_u32
- `attr_get_u64` - attr_get_u64 (attr) [Functions]. Decode an attribute whose payload is an unsigned 64-bit integer. Values larger than `INT64_MAX` are clamped to `INT64_MAX` because Lua integers are signed. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.nl.html#attr_get_u64
- `attr_get_u8` - attr_get_u8 (attr) [Functions]. Decode an attribute whose payload is an unsigned 8-bit integer. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.nl.html#attr_get_u8
- `nlmsg` - nlmsg (type, flags[, seq=0[, size=4096]]) [Functions]. Create a new netlink message builder. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.nl.html#nlmsg
- `nlmsg:binary` - nlmsg:binary () [Class nlmsg]. Serialize a message builder to a binary string. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.nl.html#nlmsg:binary
- `nlmsg:put` - nlmsg:put (data) [Class nlmsg]. Append raw bytes to the message payload. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.nl.html#nlmsg:put
- `nlmsg:put_attr` - nlmsg:put_attr (type, value) [Class nlmsg]. Append a netlink attribute with an arbitrary payload. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.nl.html#nlmsg:put_attr
- `nlmsg:put_attr_flag` - nlmsg:put_attr_flag (type) [Class nlmsg]. Append a flag attribute (attribute with zero-length payload). Docs: https://zhaojh329.github.io/lua-eco/modules/eco.nl.html#nlmsg:put_attr_flag
- `nlmsg:put_attr_nest_end` - nlmsg:put_attr_nest_end () [Class nlmsg]. End the current nested attribute. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.nl.html#nlmsg:put_attr_nest_end
- `nlmsg:put_attr_nest_start` - nlmsg:put_attr_nest_start (type) [Class nlmsg]. Start a nested attribute. After calling this, subsequent attributes appended to the message will be counted into the nested attribute's length until @{nlmsg:put_attr_nest_end} is called. Note: this implementation tracks a single active nest level. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.nl.html#nlmsg:put_attr_nest_start
- `nlmsg:put_attr_str` - nlmsg:put_attr_str (type, value) [Class nlmsg]. Append an attribute whose payload is a string (without trailing NUL). This uses `strlen()` and therefore cannot be used for strings containing embedded `\0` bytes. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.nl.html#nlmsg:put_attr_str
- `nlmsg:put_attr_strz` - nlmsg:put_attr_strz (type, value) [Class nlmsg]. Append an attribute whose payload is a NUL-terminated string. This uses `strlen()` and appends the terminating NUL. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.nl.html#nlmsg:put_attr_strz
- `nlmsg:put_attr_u16` - nlmsg:put_attr_u16 (type, value) [Class nlmsg]. Append an attribute whose payload is an unsigned 16-bit integer. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.nl.html#nlmsg:put_attr_u16
- `nlmsg:put_attr_u32` - nlmsg:put_attr_u32 (type, value) [Class nlmsg]. Append an attribute whose payload is an unsigned 32-bit integer. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.nl.html#nlmsg:put_attr_u32
- `nlmsg:put_attr_u64` - nlmsg:put_attr_u64 (type, value) [Class nlmsg]. Append an attribute whose payload is an unsigned 64-bit integer. Note: if Lua integers are 32-bit on the current build, values outside the 32-bit range may lose precision. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.nl.html#nlmsg:put_attr_u64
- `nlmsg:put_attr_u8` - nlmsg:put_attr_u8 (type, value) [Class nlmsg]. Append an attribute whose payload is an unsigned 8-bit integer. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.nl.html#nlmsg:put_attr_u8
- `nlmsg_ker` - nlmsg_ker (data) [Functions]. Create a parser for a received netlink datagram. The returned object can iterate over all messages within the datagram. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.nl.html#nlmsg_ker
- `nlmsg_ker:next` - nlmsg_ker:next () [Class nlmsg_ker]. Iterate to the next netlink message in the received datagram. The returned table contains header fields for the current message. When there are no more messages, returns `nil`. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.nl.html#nlmsg_ker:next
- `nlmsg_ker:parse_attr` - nlmsg_ker:parse_attr (offset) [Class nlmsg_ker]. Parse netlink attributes from the current message. This parses the payload region starting at `offset` and returns a table indexed by attribute type. Each value is a binary string representing the `struct nlattr` (including header). Use the module-level accessors (e.g. @{attr_get_u32}, @{attr_get_str}) to decode the returned attributes. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.nl.html#nlmsg_ker:parse_attr
- `nlmsg_ker:parse_error` - nlmsg_ker:parse_error () [Class nlmsg_ker]. Parse an `NLMSG_ERROR` message. On success, returns the `error` field from `struct nlmsgerr`. Typically, `0` means ACK/success; a negative value is `-errno`. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.nl.html#nlmsg_ker:parse_error
- `nlmsg_ker:payload` - nlmsg_ker:payload () [Class nlmsg_ker]. Get the payload of the current netlink message. The current message is the one most recently selected by @{nlmsg_ker:next}. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.nl.html#nlmsg_ker:payload
- `nlsocket:add_membership` - nlsocket:add_membership (group) [Class nlsocket]. Subscribe to a multicast group. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.nl.html#nlsocket:add_membership
- `nlsocket:bind` - nlsocket:bind (groups[, pid]) [Class nlsocket]. Bind the netlink socket. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.nl.html#nlsocket:bind
- `nlsocket:close` - nlsocket:close () [Class nlsocket]. Close the socket. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.nl.html#nlsocket:close
- `nlsocket:drop_membership` - nlsocket:drop_membership (group) [Class nlsocket]. Unsubscribe from a multicast group. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.nl.html#nlsocket:drop_membership
- `nlsocket:recv` - nlsocket:recv ([n=8192[, timeout]]) [Class nlsocket]. Receive data from the netlink socket. The return value is a message parser created by @{nl.nlmsg_ker}. The parser may contain multiple netlink messages; iterate them with @{nlmsg_ker:next}. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.nl.html#nlsocket:recv
- `nlsocket:recv_messages` - nlsocket:recv_messages ([on_msg[, on_error[, n=8192[, timeout]]]]) [Class nlsocket]. Receive and dispatch netlink messages in a loop. This is intended for event subscription sockets that only receive multicast notifications. Callback return conventions: - `true`: stop loop and return success - `false, err`: stop loop and return error - `nil`: continue Docs: https://zhaojh329.github.io/lua-eco/modules/eco.nl.html#nlsocket:recv_messages
- `nlsocket:request_ack` - nlsocket:request_ack (msg[, on_error]) [Class nlsocket]. Send a request and wait for an ACK (`NLMSG_ERROR` with error=0). Docs: https://zhaojh329.github.io/lua-eco/modules/eco.nl.html#nlsocket:request_ack
- `nlsocket:request_dump` - nlsocket:request_dump (msg[, on_msg[, on_error]]) [Class nlsocket]. Send a request and iterate reply messages until `NLMSG_DONE`. Callback return conventions: - `true`: stop early and return success - `false, err`: stop and return error - `nil`: continue Docs: https://zhaojh329.github.io/lua-eco/modules/eco.nl.html#nlsocket:request_dump
- `nlsocket:send` - nlsocket:send (msg) [Class nlsocket]. Send a netlink message. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.nl.html#nlsocket:send
- `open` - open (protocol) [Functions]. Create a netlink socket. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.nl.html#open
- `parse_attr_nested` - parse_attr_nested (nest) [Functions]. Parse attributes from a nested attribute. The returned table is indexed by attribute type. Each value is a raw attribute binary string (including header), compatible with `attr_get_*`. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.nl.html#parse_attr_nested

## eco.nl80211
- `add_interface` - add_interface (phy, ifname[, attrs]) [Functions]. Add a wireless interface. `phy` may be a PHY name (string) or PHY index (number). Supported `attrs` keys: - `type` (int): interface type (`IFTYPE_*`) - `mac` (string): MAC address as "xx:xx:.." - `4addr` (boolean) Docs: https://zhaojh329.github.io/lua-eco/modules/eco.nl80211.html#add_interface
- `bss` - bss [Tables]. BSS info returned by @{nl80211.scan} dump. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.nl80211.html#bss
- `channel_type_name` - channel_type_name (typ) [Functions]. Get readable channel type name. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.nl80211.html#channel_type_name
- `del_interface` - del_interface (ifname) [Functions]. Delete a wireless interface. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.nl80211.html#del_interface
- `escape_ssid` - escape_ssid (ssid) [Functions]. Escape SSID bytes for display. Non-printable bytes are escaped as `\\xNN`. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.nl80211.html#escape_ssid
- `freq_to_band` - freq_to_band (freq) [Functions]. Convert frequency (MHz) to band. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.nl80211.html#freq_to_band
- `freq_to_channel` - freq_to_channel (freq) [Functions]. Convert frequency (MHz) to channel number. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.nl80211.html#freq_to_channel
- `ftype_name` - ftype_name (typ, subtype) [Functions]. Get readable 802.11 frame type/subtype name. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.nl80211.html#ftype_name
- `get_freqlist` - get_freqlist (phy) [Functions]. Get supported frequencies for a PHY. Returns an array of tables with fields: - `band` (number) - `freq` (int) - `channel` (int) - `flags` (table) Docs: https://zhaojh329.github.io/lua-eco/modules/eco.nl80211.html#get_freqlist
- `get_interface` - get_interface (ifname) [Functions]. Get interface info. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.nl80211.html#get_interface
- `get_interfaces` - get_interfaces ([phy]) [Functions]. Dump interfaces. If `phy` is provided, filters by PHY index. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.nl80211.html#get_interfaces
- `get_link` - get_link (ifname) [Functions]. Get currently associated BSS on an interface. This performs a scan dump and finds an entry with `status` of `associated` (or `ibss_joined`). If possible, it also augments the BSS table with station statistics (rates, bytes, signal, etc.). Docs: https://zhaojh329.github.io/lua-eco/modules/eco.nl80211.html#get_link
- `get_noise` - get_noise (ifname) [Functions]. Get noise level (dBm). Convenience wrapper over @{get_surveys}. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.nl80211.html#get_noise
- `get_protocol_features` - get_protocol_features (phy) [Functions]. Get protocol features bitmask. `phy` may be a PHY name or PHY index. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.nl80211.html#get_protocol_features
- `get_station` - get_station (ifname, mac) [Functions]. Get station info for a single peer. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.nl80211.html#get_station
- `get_stations` - get_stations (ifname) [Functions]. Dump stations on an interface. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.nl80211.html#get_stations
- `get_surveys` - get_surveys (ifname) [Functions]. Get survey information. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.nl80211.html#get_surveys
- `iftype_name` - iftype_name (iftype) [Functions]. Get readable interface type name. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.nl80211.html#iftype_name
- `interface` - interface [Tables]. Interface info returned by @{nl80211.get_interface} / @{nl80211.get_interfaces}. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.nl80211.html#interface
- `phy_lookup` - phy_lookup (name) [Functions]. Resolve a PHY name (e.g. "phy0") to PHY index. Reads `/sys/class/ieee80211/ /index`. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.nl80211.html#phy_lookup
- `scan` - scan (action, params) [Functions]. Scan operations. - `action == 'trigger'`: trigger scan (ACK) - `action == 'dump'`: dump scan results (returns array of @{bss}) - `action == 'abort'`: abort scan (ACK) `params` fields: - `ifname` (string, required) - `ssids` (table, optional): list of SSIDs; pass `{''}` for wildcard - `freqs` (table, optional): list of frequencies in MHz - `ie` (string, optional): extra IEs - `keep_elems` (boolean, optional): include raw `elems` in BSS results Docs: https://zhaojh329.github.io/lua-eco/modules/eco.nl80211.html#scan
- `set_interface` - set_interface (ifname[, attrs]) [Functions]. Set wireless interface attributes. Uses the same `attrs` keys as @{add_interface}. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.nl80211.html#set_interface
- `station` - station [Tables]. Station info returned by @{nl80211.get_station} / @{nl80211.get_stations}. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.nl80211.html#station
- `survey` - survey [Tables]. Survey info returned by @{nl80211.get_surveys}. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.nl80211.html#survey
- `wait_event` - wait_event (grp_name, timeout, cb[, data]) [Functions]. Wait for a nl80211 multicast event. Subscribes to the given multicast group and receives messages until the callback stops the loop. The callback `cb(cmd, attrs, data)` should return: - `true` to stop and return success - `false, err` to stop and return error - `nil` to continue waiting Docs: https://zhaojh329.github.io/lua-eco/modules/eco.nl80211.html#wait_event
- `width_name` - width_name (width) [Functions]. Get readable channel width name. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.nl80211.html#width_name

## eco.packet
- `arp` - arp (op[, sha="00:00:00:00:00:00"[, sip="0.0.0.0"[, tha="00:00:00:00:00:00"[, tip="0.0.0.0"]]]]) [Functions]. Build an ARP packet. Common operations are `socket.ARPOP_REQUEST` and `socket.ARPOP_REPLY`. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.packet.html#arp
- `ether` - ether (source, dest, proto[, data=""]) [Functions]. Build an Ethernet frame. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.packet.html#ether
- `from_ether` - from_ether (data) [Functions]. Decode an Ethernet frame. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.packet.html#from_ether
- `from_icmp` - from_icmp (data) [Functions]. Decode a raw ICMP packet. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.packet.html#from_icmp
- `from_icmp6` - from_icmp6 (data) [Functions]. Decode a raw ICMPv6 packet. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.packet.html#from_icmp6
- `from_ip` - from_ip (data) [Functions]. Decode a raw IPv4 packet. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.packet.html#from_ip
- `from_ip6` - from_ip6 (data) [Functions]. Decode a raw IPv6 packet. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.packet.html#from_ip6
- `from_radiotap` - from_radiotap (data) [Functions]. Decode an IEEE 802.11 frame from a radiotap packet. This parser extracts commonly used management/data fields and selected information elements (for example SSID in beacon/probe frames). Docs: https://zhaojh329.github.io/lua-eco/modules/eco.packet.html#from_radiotap
- `icmp` - icmp (typ, code, id, sequence[, data=""[, checksum=false]]) [Functions]. Build an ICMP echo or echo-reply packet. `typ` must be one of `socket.ICMP_ECHO` or `socket.ICMP_ECHOREPLY`. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.packet.html#icmp
- `icmp6` - icmp6 (typ, code, id, sequence[, data=""[, checksum=false]]) [Functions]. Build an ICMPv6 echo request or echo reply packet. `typ` must be one of `socket.ICMPV6_ECHO_REQUEST` or `socket.ICMPV6_ECHO_REPLY`. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.packet.html#icmp6
- `ip` - ip (saddr, daddr, protocol[, data=""]) [Functions]. Build an IPv4 packet. This creates a minimal IPv4 header (no options) and computes header checksum automatically. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.packet.html#ip
- `ParsedPacket:next` - ParsedPacket:next () [Class ParsedPacket]. Decode the next protocol layer from current packet payload. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.packet.html#ParsedPacket:next
- `tcp` - tcp (source, dest, seq, ack_seq[, flags[, window=false[, saddr=false[, daddr=false[, data=false]]]]]) [Functions]. Build a TCP packet (without options). The header length is fixed to 20 bytes (`doff = 5`), i.e. TCP options are not included. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.packet.html#tcp
- `udp` - udp (source, dest[, data=""[, saddr[, daddr]]]) [Functions]. Build a UDP packet. If both `saddr` and `daddr` are provided, UDP checksum is computed with an IPv4 pseudo-header. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.packet.html#udp

## eco.rtnl
- `ifaddrmsg` - ifaddrmsg (t) [Functions]. Build a `struct ifaddrmsg`. Missing fields default to 0. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.rtnl.html#ifaddrmsg
- `ifinfomsg` - ifinfomsg (t) [Functions]. Build a `struct ifinfomsg`. Missing fields default to 0. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.rtnl.html#ifinfomsg
- `parse_ifaddrmsg` - parse_ifaddrmsg (msg) [Functions]. Parse `struct ifaddrmsg` from a netlink message. The input message must currently point to an `RTM_NEWADDR` message. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.rtnl.html#parse_ifaddrmsg
- `parse_ifinfomsg` - parse_ifinfomsg (msg) [Functions]. Parse `struct ifinfomsg` from a netlink message. The input message must currently point to an `RTM_NEWLINK` or `RTM_DELLINK` message (see @{eco.nl.nlmsg_ker:next}). Docs: https://zhaojh329.github.io/lua-eco/modules/eco.rtnl.html#parse_ifinfomsg
- `parse_rtmsg` - parse_rtmsg (msg) [Functions]. Parse `struct rtmsg` from a netlink message. The input message must currently point to an `RTM_NEWROUTE` or `RTM_DELROUTE` message. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.rtnl.html#parse_rtmsg
- `rtgenmsg` - rtgenmsg (t) [Functions]. Build a `struct rtgenmsg`. Returns a binary string containing the packed C structure. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.rtnl.html#rtgenmsg
- `rtmsg` - rtmsg (t) [Functions]. Build a `struct rtmsg`. Missing fields default to 0. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.rtnl.html#rtmsg

## eco.shared
- `dict:close` - dict:close () [Class dict]. Close the dictionary and release associated resources. This is idempotent and is also invoked by `__gc` and `__close`. For dictionaries created by @{new}, closing also removes the backing shared-memory file. Existing processes that already opened the dictionary may continue to access it, but future @{get} calls by name fail. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.shared.html#dict:close
- `dict:del` - dict:del (key) [Class dict]. Delete a key. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.shared.html#dict:del
- `dict:expire` - dict:expire (key, exptime) [Class dict]. Update key expiration. When `exptime` is positive, the key expires after `exptime` seconds. When `exptime` is `0` or negative, expiration is cleared. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.shared.html#dict:expire
- `dict:flush_all` - dict:flush_all () [Class dict]. Flushes out all the items in the dictionary. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.shared.html#dict:flush_all
- `dict:get` - dict:get (key) [Class dict]. Get value by key. Returns value if present; otherwise returns `nil`. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.shared.html#dict:get
- `dict:get_keys` - dict:get_keys () [Class dict]. Get all keys in the dictionary. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.shared.html#dict:get_keys
- `dict:incr` - dict:incr (key, value[, exptime]) [Class dict]. Increment numeric value. The key must already exist and hold a number. If `exptime` is provided, it replaces the key TTL. If `exptime` is omitted, the previous TTL is preserved. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.shared.html#dict:incr
- `dict:set` - dict:set (key, value[, exptime]) [Class dict]. Set key to value. When `exptime` is positive, the key expires after `exptime` seconds. If `exptime` is `0` or negative, the key is stored without expiration. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.shared.html#dict:set
- `dict:ttl` - dict:ttl (key) [Class dict]. Get remaining TTL in seconds. Returns `nil` if the key does not exist. Returns `0` when the key exists but has no expiration. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.shared.html#dict:ttl
- `get` - get (name) [Functions]. Open an existing shared-memory dictionary. The returned dict is a non-owner handle and `close` will not remove the shared-memory file. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.shared.html#get
- `new` - new (name, size) [Functions]. Create a new shared-memory dictionary. The caller becomes the owner of the shared-memory file. When the owner closes this dict (or it is garbage-collected), the file is removed. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.shared.html#new

## eco.socket
- `AF_INET` - AF_INET [Fields]. Address family: IPv4. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.socket.html#AF_INET
- `AF_INET6` - AF_INET6 [Fields]. Address family: IPv6. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.socket.html#AF_INET6
- `AF_NETLINK` - AF_NETLINK [Fields]. Address family: netlink. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.socket.html#AF_NETLINK
- `AF_PACKET` - AF_PACKET [Fields]. Address family: packet interface (link layer). Docs: https://zhaojh329.github.io/lua-eco/modules/eco.socket.html#AF_PACKET
- `AF_UNIX` - AF_UNIX [Fields]. Address family: Unix domain sockets. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.socket.html#AF_UNIX
- `AF_UNSPEC` - AF_UNSPEC [Fields]. Address family: unspecified. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.socket.html#AF_UNSPEC
- `connect_tcp` - connect_tcp (ipaddr, port[, options]) [Functions]. Create and connect a TCP socket. Address family is inferred from `ipaddr`. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.socket.html#connect_tcp
- `connect_udp` - connect_udp (ipaddr, port[, options]) [Functions]. Create and connect a UDP socket. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.socket.html#connect_udp
- `connect_unix` - connect_unix (server_path[, local_path]) [Functions]. Connect to a Unix domain socket. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.socket.html#connect_unix
- `htonl` - htonl (n) [Functions]. Convert 32-bit integer from host to network byte order. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.socket.html#htonl
- `htons` - htons (n) [Functions]. Convert 16-bit integer from host to network byte order. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.socket.html#htons
- `icmp` - icmp () [Functions]. Create an ICMP (IPv4) socket. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.socket.html#icmp
- `icmp6` - icmp6 () [Functions]. Create an ICMP (IPv6) socket. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.socket.html#icmp6
- `if_indextoname` - if_indextoname (Interface) [Functions]. Convert interface index to interface name. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.socket.html#if_indextoname
- `if_nametoindex` - if_nametoindex (ifname) [Functions]. Convert interface name to interface index. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.socket.html#if_nametoindex
- `inet_aton` - inet_aton (ip) [Functions]. Convert an IPv4 address string to an integer. This is a wrapper around `inet_aton(3)` and returns `in_addr.s_addr`. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.socket.html#inet_aton
- `inet_ntoa` - inet_ntoa (addr) [Functions]. Convert an IPv4 address integer to a string. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.socket.html#inet_ntoa
- `inet_ntop` - inet_ntop (family, addr) [Functions]. Convert a binary network address to presentation format. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.socket.html#inet_ntop
- `inet_pton` - inet_pton (family, ip) [Functions]. Convert a presentation format address to binary. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.socket.html#inet_pton
- `IPPROTO_ICMP` - IPPROTO_ICMP [Fields]. Protocol number: ICMP (IPv4). Docs: https://zhaojh329.github.io/lua-eco/modules/eco.socket.html#IPPROTO_ICMP
- `IPPROTO_ICMPV6` - IPPROTO_ICMPV6 [Fields]. Protocol number: ICMPv6. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.socket.html#IPPROTO_ICMPV6
- `IPPROTO_TCP` - IPPROTO_TCP [Fields]. Protocol number: TCP. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.socket.html#IPPROTO_TCP
- `IPPROTO_UDP` - IPPROTO_UDP [Fields]. Protocol number: UDP. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.socket.html#IPPROTO_UDP
- `is_ip_address` - is_ip_address (addr) [Functions]. Check if a string is an IPv4/IPv6 address. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.socket.html#is_ip_address
- `is_ipv4_address` - is_ipv4_address (ip) [Functions]. Check whether a string is a valid IPv4 address. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.socket.html#is_ipv4_address
- `is_ipv6_address` - is_ipv6_address (ip) [Functions]. Check whether a string is a valid IPv6 address. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.socket.html#is_ipv6_address
- `listen_tcp` - listen_tcp ([ipaddr], port[, options]) [Functions]. Create, bind and listen on a TCP socket. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.socket.html#listen_tcp
- `listen_udp` - listen_udp ([ipaddr], port[, options]) [Functions]. Create and bind a UDP socket. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.socket.html#listen_udp
- `listen_unix` - listen_unix (path[, options]) [Functions]. Create, bind and listen on a Unix domain socket. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.socket.html#listen_unix
- `netlink` - netlink (protocol) [Functions]. Create a netlink raw socket. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.socket.html#netlink
- `ntohl` - ntohl (n) [Functions]. Convert 32-bit integer from network to host byte order. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.socket.html#ntohl
- `ntohs` - ntohs (n) [Functions]. Convert 16-bit integer from network to host byte order. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.socket.html#ntohs
- `open_tun` - open_tun ([dev[, opts]]) [Functions]. Open or attach a Linux TUN/TAP interface. This creates (or attaches to) a Linux TUN/TAP interface. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.socket.html#open_tun
- `SOCK_DGRAM` - SOCK_DGRAM [Fields]. Socket type: datagram. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.socket.html#SOCK_DGRAM
- `SOCK_RAW` - SOCK_RAW [Fields]. Socket type: raw. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.socket.html#SOCK_RAW
- `SOCK_STREAM` - SOCK_STREAM [Fields]. Socket type: stream. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.socket.html#SOCK_STREAM
- `socket` - socket (family, domain[, protocol=0[, options]]) [Functions]. Create a socket. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.socket.html#socket
- `socket:accept` - socket:accept ([timeout]) [Class socket]. Accept an incoming connection. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.socket.html#socket:accept
- `socket:bind` - socket:bind () [Class socket]. Bind to a local address. Arguments depend on socket family: - IPv4/IPv6: `bind(ipaddr, port)` (`ipaddr` can be nil for ANY) - Unix: `bind(path)` - Netlink: `bind(groups?, pid?)` - Packet: `bind({ ifindex=..., ifname=... })` Docs: https://zhaojh329.github.io/lua-eco/modules/eco.socket.html#socket:bind
- `socket:close` - socket:close () [Class socket]. Close the socket. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.socket.html#socket:close
- `socket:closed` - socket:closed () [Class socket]. Check whether the socket is closed. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.socket.html#socket:closed
- `socket:connect` - socket:connect () [Class socket]. Connect to a remote address. Arguments depend on socket family (same as @{socket:bind}). Docs: https://zhaojh329.github.io/lua-eco/modules/eco.socket.html#socket:connect
- `socket:getfd` - socket:getfd () [Class socket]. Get underlying file descriptor. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.socket.html#socket:getfd
- `socket:getpeername` - socket:getpeername () [Class socket]. Get peer socket address. Address table format is the same as @{socket:getsockname}. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.socket.html#socket:getpeername
- `socket:getsockname` - socket:getsockname () [Class socket]. Get local socket address. Returned address is a table. Typical fields: - `family` - IPv4/IPv6: `ipaddr`, `port` - Unix: `path` - Netlink: `pid` Docs: https://zhaojh329.github.io/lua-eco/modules/eco.socket.html#socket:getsockname
- `socket:listen` - socket:listen ([backlog]) [Class socket]. Start listening (server sockets). Docs: https://zhaojh329.github.io/lua-eco/modules/eco.socket.html#socket:listen
- `socket:read` - socket:read () [Class socket]. See @{eco.reader:read} Docs: https://zhaojh329.github.io/lua-eco/modules/eco.socket.html#socket:read
- `socket:readfull` - socket:readfull () [Class socket]. See @{eco.reader:readfull} Docs: https://zhaojh329.github.io/lua-eco/modules/eco.socket.html#socket:readfull
- `socket:readuntil` - socket:readuntil () [Class socket]. See @{eco.reader:readuntil} Docs: https://zhaojh329.github.io/lua-eco/modules/eco.socket.html#socket:readuntil
- `socket:recv` - socket:recv () [Class socket]. Alias of @{socket:read}. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.socket.html#socket:recv
- `socket:recvfrom` - socket:recvfrom (n[, timeout]) [Class socket]. Receive a datagram. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.socket.html#socket:recvfrom
- `socket:recvfull` - socket:recvfull () [Class socket]. Alias of @{socket:readfull}. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.socket.html#socket:recvfull
- `socket:send` - socket:send (data[, timeout]) [Class socket]. Send data on a connected stream socket. This method serializes concurrent writers using an internal mutex. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.socket.html#socket:send
- `socket:sendfile` - socket:sendfile (path[, len[, offset=0]]) [Class socket]. Send file contents on a connected stream socket. If `len` is omitted, sends from `offset` to the end of the file. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.socket.html#socket:sendfile
- `socket:sendto` - socket:sendto (data) [Class socket]. Send a datagram. For UDP/RAW sockets, destination address is provided after `data`. Arguments follow the same conventions as @{socket:connect}. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.socket.html#socket:sendto
- `socket:setoption` - socket:setoption (name, value) [Class socket]. Set a socket option. Supported option names: `reuseaddr`, `reuseport`, `keepalive`, `broadcast`, `mark`, `bindtodevice`, `tcp_nodelay`, `tcp_keepidle`, ... Docs: https://zhaojh329.github.io/lua-eco/modules/eco.socket.html#socket:setoption
- `socket:write` - socket:write () [Class socket]. Alias of @{socket:send}. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.socket.html#socket:write
- `socketpair` - socketpair (family, domain[, protocol=0[, options]]) [Functions]. Create a pair of connected sockets. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.socket.html#socketpair
- `tcp` - tcp () [Functions]. Create a TCP (IPv4) stream socket. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.socket.html#tcp
- `tcp6` - tcp6 () [Functions]. Create a TCP (IPv6) stream socket. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.socket.html#tcp6
- `udp` - udp () [Functions]. Create a UDP (IPv4) datagram socket. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.socket.html#udp
- `udp6` - udp6 () [Functions]. Create a UDP (IPv6) datagram socket. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.socket.html#udp6
- `unix` - unix () [Functions]. Create a Unix stream socket. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.socket.html#unix
- `unix_dgram` - unix_dgram () [Functions]. Create a Unix datagram socket. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.socket.html#unix_dgram

## eco.ssh
- `new` - new (ipaddr, port, username[, password]) [Functions]. Create a new SSH session. This call: 1. connects to the remote TCP endpoint 2. performs SSH handshake 3. attempts password authentication if the server advertises it Docs: https://zhaojh329.github.io/lua-eco/modules/eco.ssh.html#new
- `session:disconnect` - session:disconnect ([reaason[, description]]) [Class session]. Disconnect the SSH session. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.ssh.html#session:disconnect
- `session:exec` - session:exec (cmd[, timeout]) [Class session]. Execute a command on the remote host. The returned output is a concatenation of stdout and stderr. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.ssh.html#session:exec
- `session:free` - session:free () [Class session]. Close and free the session. This is also used as the `__gc` and `__close` metamethod. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.ssh.html#session:free
- `session:scp_recv` - session:scp_recv (source[, dest]) [Class session]. Receive a remote file via SCP. If `dest` is provided, the remote file will be stored to that local path and this method returns the number of bytes written. If `dest` is omitted, the whole file content is returned as a Lua string. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.ssh.html#session:scp_recv
- `session:scp_send` - session:scp_send (data, dest) [Class session]. Send data to the remote host via SCP. Creates/overwrites `dest` on the remote host. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.ssh.html#session:scp_send
- `session:scp_sendfile` - session:scp_sendfile (source, dest) [Class session]. Send a local file to the remote host via SCP. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.ssh.html#session:scp_sendfile

## eco.ssl
- `connect` - connect (ipaddr, port[, options]) [Functions]. Create a TLS client connection. Internally this calls @{eco.socket.connect_tcp} and performs a TLS handshake. `options` fields used by TLS: - `ca`: Path to CA certificate file. - `cert`: Path to client certificate file (optional, for mTLS). - `key`: Path to client private key file (optional, for mTLS). - `insecure`: When true, disables/relaxes peer verification (backend dependent). - `server_name`: SNI server name. - `ctx`: An existing ssl context object to reuse. Other fields are passed to @{eco.socket.connect_tcp}. If `options.ctx` is provided, it is reused and will NOT be freed when the ret Docs: https://zhaojh329.github.io/lua-eco/modules/eco.ssl.html#connect
- `listen` - listen (ipaddr, port[, options]) [Functions]. Create a TLS server listener. Internally this calls @{eco.socket.listen_tcp} and wraps accepted sockets with TLS using a server context. `options` fields used by TLS: - `ca`: Path to CA certificate file. - `cert`: Path to server certificate file. - `key`: Path to server private key file. - `insecure`: When true, disables/relaxes peer verification (backend dependent). Other fields are passed to @{eco.socket.listen_tcp}. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.ssl.html#listen
- `ssl_client:close` - ssl_client:close () [Class ssl_client]. Close the TLS connection. Frees internal TLS state and closes the underlying TCP socket. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.ssl.html#ssl_client:close
- `ssl_client:read` - ssl_client:read () [Class ssl_client]. See @{eco.reader:read} Docs: https://zhaojh329.github.io/lua-eco/modules/eco.ssl.html#ssl_client:read
- `ssl_client:readfull` - ssl_client:readfull () [Class ssl_client]. See @{eco.reader:readfull} Docs: https://zhaojh329.github.io/lua-eco/modules/eco.ssl.html#ssl_client:readfull
- `ssl_client:readuntil` - ssl_client:readuntil () [Class ssl_client]. See @{eco.reader:readuntil} Docs: https://zhaojh329.github.io/lua-eco/modules/eco.ssl.html#ssl_client:readuntil
- `ssl_client:recv` - ssl_client:recv () [Class ssl_client]. Alias of @{ssl_client:read}. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.ssl.html#ssl_client:recv
- `ssl_client:send` - ssl_client:send (data[, timeout]) [Class ssl_client]. Send data. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.ssl.html#ssl_client:send
- `ssl_client:sendfile` - ssl_client:sendfile (path, len[, offset[, timeout]]) [Class ssl_client]. Send file content. This is a convenience helper that reads from a file and sends exactly `len` bytes (unless EOF/error occurs). Docs: https://zhaojh329.github.io/lua-eco/modules/eco.ssl.html#ssl_client:sendfile
- `ssl_client:write` - ssl_client:write () [Class ssl_client]. Alias of @{ssl_client:send}. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.ssl.html#ssl_client:write
- `ssl_server:accept` - ssl_server:accept () [Class ssl_server]. Accept a TLS client. This accepts an incoming TCP connection and then performs a TLS handshake. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.ssl.html#ssl_server:accept
- `ssl_server:close` - ssl_server:close () [Class ssl_server]. Close the server and free its TLS context. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.ssl.html#ssl_server:close

## eco.sync
- `cond` - cond () [Functions]. Create a condition variable. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.sync.html#cond
- `cond:broadcast` - cond:broadcast () [Class cond]. Wake all waiting coroutines. All awakened waiters will receive `true` as the return value of @{cond:wait}. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.sync.html#cond:broadcast
- `cond:signal` - cond:signal ([data]) [Class cond]. Wake one waiting coroutine. If `data` is provided and is truthy, the waiter will receive `data` as the return value of @{cond:wait}; otherwise it will receive `true`. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.sync.html#cond:signal
- `cond:wait` - cond:wait ([timeout]) [Class cond]. Wait until signaled. If signaled with a non-nil *truthy* `data`, returns that `data`. Otherwise returns `true`. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.sync.html#cond:wait
- `mutex` - mutex () [Functions]. Create a mutex. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.sync.html#mutex
- `mutex:lock` - mutex:lock ([timeout]) [Class mutex]. Lock the mutex. If the mutex is already locked, the current coroutine waits until it becomes available or `timeout` expires. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.sync.html#mutex:lock
- `mutex:unlock` - mutex:unlock () [Class mutex]. Unlock the mutex. Wakes one coroutine waiting in @{mutex:lock}. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.sync.html#mutex:unlock
- `waitgroup` - waitgroup () [Functions]. Create a wait group. One coroutine calls @{waitgroup:add} to set the number of coroutines to wait for. Then each of those coroutines runs and calls @{waitgroup:done} when finished. Meanwhile, @{waitgroup:wait} can be used to block until all of them have finished. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.sync.html#waitgroup
- `waitgroup:add` - waitgroup:add (delta) [Class waitgroup]. Add delta to the wait group counter. A positive `delta` increments the number of workers to wait for. A negative `delta` decrements it. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.sync.html#waitgroup:add
- `waitgroup:done` - waitgroup:done () [Class waitgroup]. Decrement the wait group counter by one. When the counter reaches zero, all waiters are awakened. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.sync.html#waitgroup:done
- `waitgroup:wait` - waitgroup:wait ([timeout]) [Class waitgroup]. Wait until the counter becomes zero. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.sync.html#waitgroup:wait

## eco.sys
- `exec` - exec (cmd[, env]) [Functions]. Execute a program. Spawns a new process and returns a process handle object. The returned object provides methods to wait for process exit, read stdout/stderr. There are two supported calling forms: 1. Argument list form: p, err = sys.exec(cmd, arg1, arg2, ...) 2. Table form with optional environment: p, err = sys.exec({ cmd, arg1, arg2, ... }, env) In the second form, `env` is a table of environment variables. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.sys.html#exec
- `fork` - fork () [Functions]. Fork the current process. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.sys.html#fork
- `get_nprocs` - get_nprocs () [Functions]. Get number of available processors. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.sys.html#get_nprocs
- `getpid` - getpid () [Functions]. Get current process id. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.sys.html#getpid
- `getppid` - getppid () [Functions]. Get parent process id. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.sys.html#getppid
- `getpwnam` - getpwnam (name) [Functions]. Lookup a user by name. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.sys.html#getpwnam
- `kill` - kill (pid, sig) [Functions]. Send a signal to a process. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.sys.html#kill
- `prctl` - prctl (option[, arg]) [Functions]. Process control operations. Currently supports `PR_SET_PDEATHSIG`. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.sys.html#prctl
- `process:close` - process:close () [Class process]. Close stdout and stderr file descriptors. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.sys.html#process:close
- `process:kill` - process:kill () [Class process]. Force kill the process with SIGKILL. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.sys.html#process:kill
- `process:read_stderr` - process:read_stderr () [Class process]. Read from process stderr. See @{eco.reader:read} Docs: https://zhaojh329.github.io/lua-eco/modules/eco.sys.html#process:read_stderr
- `process:read_stdout` - process:read_stdout () [Class process]. Read from process stdout. See @{eco.reader:read} Docs: https://zhaojh329.github.io/lua-eco/modules/eco.sys.html#process:read_stdout
- `process:signal` - process:signal (sig) [Class process]. Send a signal to the process. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.sys.html#process:signal
- `process:stop` - process:stop ([timeout=3]) [Class process]. Stop the process gracefully, then force kill if needed. This sends SIGTERM first, waits up to `timeout` seconds, then sends SIGKILL if the process is still alive. Waiting remains coroutine-based. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.sys.html#process:stop
- `process:wait` - process:wait ([timeout]) [Class process]. Wait for the process to exit. If the child has already exited before calling this method, it returns immediately with the status cached on this process handle. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.sys.html#process:wait
- `sh` - sh (cmd[, timeout=30]) [Functions]. Execute a shell command and return stdout and stderr. This is a convenience wrapper around @{exec}. It accepts a command string or a table of arguments. If a string is provided, it will be executed using `/bin/sh -c`. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.sys.html#sh
- `signal` - signal (signum, cb, Additional) [Functions]. Listen for a specific signal and invoke a callback asynchronously. This function wraps `signalfd` and spawns a coroutine to continuously read the signal. When the specified signal `sig` is received, the callback `cb` is invoked with any additional arguments. The returned @{signal_handle} object controls the listener lifetime. Call `sig:close()` to stop listening. Internally this function blocks `signum` in the process mask and uses `signalfd` for delivery. The signal will be unblocked when the listener is closed. Note: `SIGCHLD` is reserved by eco's scheduler for child process reaping and must Docs: https://zhaojh329.github.io/lua-eco/modules/eco.sys.html#signal
- `signal_handle:close` - signal_handle:close () [Class signal_handle]. Stop listening for the signal and release resources. This closes the internal `signalfd`, cancels pending read operations, and restores the process signal mask for this signal. Calling this method multiple times is safe. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.sys.html#signal_handle:close
- `spawn` - spawn (f) [Functions]. Spawn a new process to run a Lua function. This function forks a child process and runs the given function `f` inside it. The child process will be terminated if the parent dies (`PR_SET_PDEATHSIG = SIGKILL`). Docs: https://zhaojh329.github.io/lua-eco/modules/eco.sys.html#spawn
- `strerror` - strerror (errno) [Functions]. Convert errno value to message. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.sys.html#strerror
- `uptime` - uptime () [Functions]. Get system uptime. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.sys.html#uptime
- `waitpid` - waitpid (pid) [Functions]. Wait for a child process status change (non-blocking). This is a thin wrapper around `waitpid(pid, ..., WNOHANG | WUNTRACED)`. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.sys.html#waitpid

## eco.termios
- `attr:clone` - attr:clone () [Class attr]. Clone attributes. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.termios.html#attr:clone
- `attr:clr_flag` - attr:clr_flag (type, flag) [Class attr]. Clear a flag bit in the attributes. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.termios.html#attr:clr_flag
- `attr:get_ispeed` - attr:get_ispeed () [Class attr]. Get input baud rate. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.termios.html#attr:get_ispeed
- `attr:get_ospeed` - attr:get_ospeed () [Class attr]. Get output baud rate. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.termios.html#attr:get_ospeed
- `attr:set_cc` - attr:set_cc (name, value) [Class attr]. Set a control character. `name` is one of the `V*` indices (e.g. `termios.VMIN`, `termios.VTIME`). Docs: https://zhaojh329.github.io/lua-eco/modules/eco.termios.html#attr:set_cc
- `attr:set_flag` - attr:set_flag (type, flag) [Class attr]. Set a flag bit in the attributes. `type` selects which flag field is modified: - `"i"`: input flags (`c_iflag`) - `"o"`: output flags (`c_oflag`) - `"c"`: control flags (`c_cflag`) - `"l"`: local flags (`c_lflag`) Docs: https://zhaojh329.github.io/lua-eco/modules/eco.termios.html#attr:set_flag
- `attr:set_ispeed` - attr:set_ispeed (speed) [Class attr]. Set input baud rate. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.termios.html#attr:set_ispeed
- `attr:set_ospeed` - attr:set_ospeed (speed) [Class attr]. Set output baud rate. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.termios.html#attr:set_ospeed
- `attr:set_speed` - attr:set_speed (speed) [Class attr]. Set both input and output baud rate. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.termios.html#attr:set_speed
- `tcflow` - tcflow (fd, action) [Functions]. Suspend or restart terminal I/O. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.termios.html#tcflow
- `tcflush` - tcflush (fd, queue_selector) [Functions]. Flush terminal I/O queues. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.termios.html#tcflush
- `tcgetattr` - tcgetattr (fd) [Functions]. Get terminal attributes. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.termios.html#tcgetattr
- `tcsetattr` - tcsetattr (fd, actions, attr) [Functions]. Set terminal attributes. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.termios.html#tcsetattr

## eco.time
- `at` - at (delay, cb[, ...]) [Functions]. Create and start a timer with a relative delay. This is a convenience wrapper around `timer` + `timer:set`. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.time.html#at
- `CLOCK_MONOTONIC` - CLOCK_MONOTONIC [Fields]. Clock id for monotonic time. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.time.html#CLOCK_MONOTONIC
- `CLOCK_REALTIME` - CLOCK_REALTIME [Fields]. Clock id for realtime clock. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.time.html#CLOCK_REALTIME
- `now` - now () [Functions]. Get current time Docs: https://zhaojh329.github.io/lua-eco/modules/eco.time.html#now
- `on` - on (ts, cb[, ...]) [Functions]. Create and start a timer with an absolute timestamp. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.time.html#on
- `sleep` - sleep (delay) [Functions]. Alias of @{eco.sleep}. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.time.html#sleep
- `TFD_TIMER_ABSTIME` - TFD_TIMER_ABSTIME [Fields]. `timerfd_settime()` flag: interpret `it_value` as an absolute time. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.time.html#TFD_TIMER_ABSTIME
- `timer` - timer (cb[, ...]) [Functions]. Create a timer (not started). The timer will not start until you call `timer:set`. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.time.html#timer
- `timer:cancel` - timer:cancel () [Class timer]. Cancel the timer callback. This cancels the pending read waiting for the timer to expire. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.time.html#timer_methods:cancel
- `timer:close` - timer:close () [Class timer]. Close the timer and release its file descriptor. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.time.html#timer_methods:close
- `timer:set` - timer:set (delay) [Class timer]. Arm (or re-arm) the timer. For timers created by @{timer} and @{at}, `delay` is a relative delay in seconds. For timers created by @{on}, `delay` is an absolute timestamp (seconds since epoch), and will be passed to `timerfd_settime()` with `TFD_TIMER_ABSTIME`. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.time.html#timer_methods:set

## eco.ubus
- `ARRAY` - ARRAY [Fields]. Blob message policy type: array. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.ubus.html#ARRAY
- `BOOLEAN` - BOOLEAN [Fields]. Blob message policy type: boolean. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.ubus.html#BOOLEAN
- `call` - call (object, method[, params[, timeout]]) [Functions]. Call a ubus method (one-shot connection). This helper creates a temporary connection (via @{eco.ubus.connect}), performs a call and closes the connection automatically. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.ubus.html#call
- `connect` - connect ([path[, auto_reconnect=false]]) [Functions]. Connect to ubus. This creates a connection object and starts a background coroutine to dispatch events and call replies. Note: this implementation requires root privileges. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.ubus.html#connect
- `connection:add` - connection:add (object, defs) [Class connection]. Add a ubus object with method handlers. `defs` is a table mapping method name to `{ cb, policy }`. When the connection is created with `auto_reconnect = true`, objects added by this method are automatically added again after reconnect. The method callback is executed in a new coroutine as: `cb(req, msg, con)` You usually send the reply using @{connection:reply}. The callback may return a numeric ubus status code; non-number return values are treated as `0`. `policy` is a table mapping field name to policy type (e.g. `ubus.STRING`, `ubus.INT32`). Docs: https://zhaojh329.github.io/lua-eco/modules/eco.ubus.html#connection:add
- `connection:call` - connection:call (object, method[, params[, timeout]]) [Class connection]. Call an ubus method using an existing connection. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.ubus.html#connection:call
- `connection:close` - connection:close () [Class connection]. Close the connection. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.ubus.html#connection:close
- `connection:listen` - connection:listen (event, cb) [Class connection]. Listen to ubus events. When the connection is created with `auto_reconnect = true`, event listeners added by this method are automatically re-registered after reconnect. The callback is executed in a new coroutine as: `cb(event, msg, con)` Docs: https://zhaojh329.github.io/lua-eco/modules/eco.ubus.html#connection:listen
- `connection:notify` - connection:notify (object, method[, params]) [Class connection]. Send a notification from an object. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.ubus.html#connection:notify
- `connection:objects` - connection:objects () [Class connection]. List ubus objects. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.ubus.html#connection:objects
- `connection:reply` - connection:reply (req[, msg]) [Class connection]. Reply to a request. This is called from handlers registered via @{connection:add}. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.ubus.html#connection:reply
- `connection:send` - connection:send (event[, params]) [Class connection]. Send an ubus event. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.ubus.html#connection:send
- `connection:signatures` - connection:signatures (object) [Class connection]. Get the signatures of an ubus object. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.ubus.html#connection:signatures
- `connection:subscribe` - connection:subscribe (path, cb[, auto=false]) [Class connection]. Subscribe to notifications of an ubus object. The callback is executed in a new coroutine as: `cb(method, msg, con)` Docs: https://zhaojh329.github.io/lua-eco/modules/eco.ubus.html#connection:subscribe
- `connection:unsubscribe` - connection:unsubscribe (subscriber) [Class connection]. Unsubscribe from an ubus object notifications. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.ubus.html#connection:unsubscribe
- `DOUBLE` - DOUBLE [Fields]. Blob message policy type: double. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.ubus.html#DOUBLE
- `INT16` - INT16 [Fields]. Blob message policy type: int16. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.ubus.html#INT16
- `INT32` - INT32 [Fields]. Blob message policy type: int32. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.ubus.html#INT32
- `INT64` - INT64 [Fields]. Blob message policy type: int64. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.ubus.html#INT64
- `INT8` - INT8 [Fields]. Blob message policy type: int8. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.ubus.html#INT8
- `objects` - objects () [Functions]. List ubus objects (one-shot connection). Docs: https://zhaojh329.github.io/lua-eco/modules/eco.ubus.html#objects
- `send` - send (event[, params]) [Functions]. Send an ubus event (one-shot connection). This helper creates a temporary connection (via @{eco.ubus.connect}), sends the event and closes the connection automatically. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.ubus.html#send
- `signatures` - signatures (object) [Functions]. Get the signatures of an ubus object (one-shot connection). Docs: https://zhaojh329.github.io/lua-eco/modules/eco.ubus.html#signatures
- `STATUS_CONNECTION_FAILED` - STATUS_CONNECTION_FAILED [Fields]. Return status: connection failed. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.ubus.html#STATUS_CONNECTION_FAILED
- `STATUS_INVALID_ARGUMENT` - STATUS_INVALID_ARGUMENT [Fields]. Return status: invalid argument. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.ubus.html#STATUS_INVALID_ARGUMENT
- `STATUS_INVALID_COMMAND` - STATUS_INVALID_COMMAND [Fields]. Return status: invalid command. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.ubus.html#STATUS_INVALID_COMMAND
- `STATUS_METHOD_NOT_FOUND` - STATUS_METHOD_NOT_FOUND [Fields]. Return status: method not found. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.ubus.html#STATUS_METHOD_NOT_FOUND
- `STATUS_NO_DATA` - STATUS_NO_DATA [Fields]. Return status: no data. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.ubus.html#STATUS_NO_DATA
- `STATUS_NOT_FOUND` - STATUS_NOT_FOUND [Fields]. Return status: object not found. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.ubus.html#STATUS_NOT_FOUND
- `STATUS_NOT_SUPPORTED` - STATUS_NOT_SUPPORTED [Fields]. Return status: not supported. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.ubus.html#STATUS_NOT_SUPPORTED
- `STATUS_OK` - STATUS_OK [Fields]. Return status: success. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.ubus.html#STATUS_OK
- `STATUS_PERMISSION_DENIED` - STATUS_PERMISSION_DENIED [Fields]. Return status: permission denied. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.ubus.html#STATUS_PERMISSION_DENIED
- `STATUS_TIMEOUT` - STATUS_TIMEOUT [Fields]. Return status: timeout. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.ubus.html#STATUS_TIMEOUT
- `STATUS_UNKNOWN_ERROR` - STATUS_UNKNOWN_ERROR [Fields]. Return status: unknown error. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.ubus.html#STATUS_UNKNOWN_ERROR
- `STRING` - STRING [Fields]. Blob message policy type: string. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.ubus.html#STRING
- `TABLE` - TABLE [Fields]. Blob message policy type: table. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.ubus.html#TABLE

## eco.uci
- `cursor` - cursor ([confdir[, savedir]]) [Functions]. Create a UCI cursor. Call forms: - `uci.cursor()` (use default dirs) - `uci.cursor(confdir)` - `uci.cursor(confdir, savedir)` Docs: https://zhaojh329.github.io/lua-eco/modules/eco.uci.html#cursor
- `cursor:add` - cursor:add (package, type) [Class cursor]. Add a new section. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.uci.html#cursor:add
- `cursor:close` - cursor:close () [Class cursor]. Close the cursor and free underlying libuci context. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.uci.html#cursor:close
- `cursor:commit` - cursor:commit (package) [Class cursor]. Commit a package (write changes). Docs: https://zhaojh329.github.io/lua-eco/modules/eco.uci.html#cursor:commit
- `cursor:delete` - cursor:delete (package[, section[, option]]) [Class cursor]. Delete a section or option. Accepted call forms: - `c:delete('p.s.o')` / `c:delete('p.s')` - `c:delete('p', 's')` / `c:delete('p', 's', 'o')` Docs: https://zhaojh329.github.io/lua-eco/modules/eco.uci.html#cursor:delete
- `cursor:each` - cursor:each (package[, type]) [Class cursor]. Get an iterator over sections. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.uci.html#cursor:each
- `cursor:foreach` - cursor:foreach (package[, type], cb) [Class cursor]. Iterate sections and call a callback. The callback is invoked as `cb(section_table)`. Return `false` from the callback to stop iteration early. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.uci.html#cursor:foreach
- `cursor:get` - cursor:get (package[, section[, option]]) [Class cursor]. Get a UCI value. Accepted call forms: - `c:get('p.s.o')` - `c:get('p', 's')` (returns section `type, name`) - `c:get('p', 's', 'o')` Return values: - option: string value, or a list table for list options - section: `type, name` (two strings) - package: a table of sections On error: returns `nil, err`. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.uci.html#cursor:get
- `cursor:get_all` - cursor:get_all (package[, section[, option]]) [Class cursor]. Get a UCI value, returning full section tables. Similar to @{cursor:get}, but when pointing to a section it returns a table containing: - `['.anonymous']` boolean - `['.type']` string - `['.name']` string - `['.index']` integer (when available) - plus all options under their option names Docs: https://zhaojh329.github.io/lua-eco/modules/eco.uci.html#cursor:get_all
- `cursor:get_confdir` - cursor:get_confdir () [Class cursor]. Get current configuration directory. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.uci.html#cursor:get_confdir
- `cursor:get_savedir` - cursor:get_savedir () [Class cursor]. Get current save directory. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.uci.html#cursor:get_savedir
- `cursor:list_configs` - cursor:list_configs () [Class cursor]. List available config files. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.uci.html#cursor:list_configs
- `cursor:load` - cursor:load (package) [Class cursor]. Load a UCI package. This first unloads any previously loaded package with the same name. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.uci.html#cursor:load
- `cursor:rename` - cursor:rename (package[, section[, option[, value]]]) [Class cursor]. Rename a section or option. Accepted call forms match @{cursor:set} (without list values). Docs: https://zhaojh329.github.io/lua-eco/modules/eco.uci.html#cursor:rename
- `cursor:reorder` - cursor:reorder (package[, section[, index]]) [Class cursor]. Reorder a section by index. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.uci.html#cursor:reorder
- `cursor:revert` - cursor:revert (package[, section[, option]]) [Class cursor]. Revert changes. This can revert a whole package or a specific section/option. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.uci.html#cursor:revert
- `cursor:save` - cursor:save (package) [Class cursor]. Save a package. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.uci.html#cursor:save
- `cursor:set` - cursor:set (package[, section[, option[, value]]]) [Class cursor]. Set a package/section/option. Accepted call forms: - `c:set('p.s.o=v')` or `c:set('p.s=v')` - `c:set('p', 's', 'o', 'v')` - `c:set('p', 's', 'v')` (sets section type?) - `c:set('p', 's', 'o', {'v1', 'v2'})` (list option) Docs: https://zhaojh329.github.io/lua-eco/modules/eco.uci.html#cursor:set
- `cursor:set_confdir` - cursor:set_confdir (dir) [Class cursor]. Set configuration directory. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.uci.html#cursor:set_confdir
- `cursor:set_savedir` - cursor:set_savedir (dir) [Class cursor]. Set save directory. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.uci.html#cursor:set_savedir
- `cursor:unload` - cursor:unload (package) [Class cursor]. Unload a previously loaded package. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.uci.html#cursor:unload

## eco.websocket
- `connect` - connect (uri[, opts]) [Functions]. Connect to a WebSocket server. This performs an HTTP upgrade handshake for `ws://` or `wss://` URIs and returns a WebSocket connection on success. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.websocket.html#connect
- `connection:recv_frame` - connection:recv_frame ([timeout]) [Class connection]. Receive a single WebSocket frame. Return convention: - On success: `data, typ, err` - On failure: `nil, nil, err` `typ` is one of: `'text'`, `'binary'`, `'continuation'`, `'close'`, `'ping'`, `'pong'`. For `typ == 'close'`, `err` carries the close status code (number) when present, and `data` carries the close reason string. For fragmented messages, `err == 'again'` indicates that more frames are expected to complete the message. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.websocket.html#connection:recv_frame
- `connection:send_binary` - connection:send_binary ([data]) [Class connection]. Send a binary frame. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.websocket.html#connection:send_binary
- `connection:send_close` - connection:send_close ([code[, msg]]) [Class connection]. Send a close frame. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.websocket.html#connection:send_close
- `connection:send_frame` - connection:send_frame (fin, opcode[, payload]) [Class connection]. Send a raw WebSocket frame. `opcode` values follow RFC 6455: - `0x1` text - `0x2` binary - `0x8` close - `0x9` ping - `0xA` pong Docs: https://zhaojh329.github.io/lua-eco/modules/eco.websocket.html#connection:send_frame
- `connection:send_ping` - connection:send_ping ([data]) [Class connection]. Send a ping frame. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.websocket.html#connection:send_ping
- `connection:send_pong` - connection:send_pong ([data]) [Class connection]. Send a pong frame. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.websocket.html#connection:send_pong
- `connection:send_text` - connection:send_text ([data]) [Class connection]. Send a text frame. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.websocket.html#connection:send_text
- `ConnectOptions` - ConnectOptions [Tables]. Options table for @{websocket.connect}. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.websocket.html#ConnectOptions
- `upgrade` - upgrade (con, req[, opts]) [Functions]. Upgrade an @{eco.http.server} connection to WebSocket. This performs server-side validation of the WebSocket handshake and sends the `101 Switching Protocols` response. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.websocket.html#upgrade
- `WebSocketOptions` - WebSocketOptions [Tables]. Options table for WebSocket connections. Docs: https://zhaojh329.github.io/lua-eco/modules/eco.websocket.html#WebSocketOptions
