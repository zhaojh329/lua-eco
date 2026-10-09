#!/usr/bin/env eco

local test = require 'test'
local dns = require 'eco.dns'
local socket = require 'eco.socket'
local eco = require 'eco'

local SENTINEL = {}

local function encode_name(name)
    local out = {}

    for label in name:gmatch('([^.]+)') do
        out[#out + 1] = string.char(#label) .. label
    end

    out[#out + 1] = '\0'

    return table.concat(out)
end

local function decode_name_no_ptr(buf, pos)
    local labels = {}
    local p = pos

    while true do
        local n = string.byte(buf, p)
        assert(n ~= nil, 'bad dns name: truncated')

        if n == 0 then
            p = p + 1
            break
        end

        labels[#labels + 1] = buf:sub(p + 1, p + n)
        p = p + n + 1
    end

    return table.concat(labels, '.'), p
end

local function parse_dns_request(req)
    local id, flags, nqs = string.unpack('>I2I2I2', req)
    local qname, p = decode_name_no_ptr(req, 13)
    local qtype, qclass = string.unpack('>I2I2', req:sub(p))

    return {
        id = id,
        flags = flags,
        nqs = nqs,
        qname = qname,
        qtype = qtype,
        qclass = qclass
    }
end

local function build_a_response(req_meta, address, flags)
    local a, b, c, d = address:match('^(%d+)%.(%d+)%.(%d+)%.(%d+)$')
    assert(a and b and c and d, 'bad IPv4 literal for A response')

    local question = encode_name(req_meta.qname) .. string.pack('>I2I2', req_meta.qtype, req_meta.qclass)

    local answer = string.char(0xc0, 0x0c)
        .. string.pack('>I2I2I4I2', dns.TYPE_A, dns.CLASS_IN, 30, 4)
        .. string.char(tonumber(a), tonumber(b), tonumber(c), tonumber(d))

    return string.pack('>I2I2I2I2I2I2', req_meta.id, flags or 0x8180, 1, 1, 0, 0)
        .. question
        .. answer
end

local function build_error_response(req_meta, rcode)
    local question = encode_name(req_meta.qname) .. string.pack('>I2I2', req_meta.qtype, req_meta.qclass)
    local flags = 0x8000 | (rcode & 0xf)

    return string.pack('>I2I2I2I2I2I2', req_meta.id, flags, 1, 0, 0, 0)
        .. question
end

local function restore_modules(saved)
    for name, value in pairs(saved) do
        if value == SENTINEL then
            package.loaded[name] = nil
        else
            package.loaded[name] = value
        end
    end
end

local function with_stubbed_dns(factory, fn)
    local module_names = {
        'eco.dns',
        'eco.socket',
        'eco.internal.file',
        'eco.internal.dns',
        'eco.time'
    }

    local saved_modules = {}

    for _, name in ipairs(module_names) do
        if package.loaded[name] == nil then
            saved_modules[name] = SENTINEL
        else
            saved_modules[name] = package.loaded[name]
        end
    end

    local saved_io_lines = io.lines
    local env = factory(saved_io_lines)

    io.lines = env.io_lines

    package.loaded['eco.socket'] = env.socket
    package.loaded['eco.internal.file'] = env.file
    package.loaded['eco.time'] = env.time
    if env.dns then
        package.loaded['eco.internal.dns'] = env.dns
    end
    package.loaded['eco.dns'] = nil

    local ok, mod_or_err = pcall(require, 'eco.dns')
    if not ok then
        io.lines = saved_io_lines
        restore_modules(saved_modules)
        error(mod_or_err)
    end

    local dns_mod = mod_or_err

    local run_ok, run_err = pcall(fn, dns_mod, env.state)

    io.lines = saved_io_lines
    restore_modules(saved_modules)

    assert(run_ok, run_err)
end

local function make_env(cfg)
    cfg = cfg or {}

    local state = {
        now = 0,
        connect_records = {},
        udp_calls = 0,
        udp6_calls = 0,
        send_records = {},
        recv_records = {},
        setoptions = {},
        close_count = 0
    }

    local function is_ipv4(host)
        if cfg.is_ipv4 then
            return cfg.is_ipv4(host)
        end

        return type(host) == 'string' and host:match('^%d+%.%d+%.%d+%.%d+$') ~= nil
    end

    local function is_ipv6(host)
        if cfg.is_ipv6 then
            return cfg.is_ipv6(host)
        end

        return type(host) == 'string' and host:find(':', 1, true) ~= nil
    end

    local function make_socket(family)
        local idx = #state.recv_records + 1

        local s = {}
        local recv_count = 0

        function s:connect(host, port)
            state.connect_records[idx] = { host, port }
            if cfg.connect_error then
                return nil, cfg.connect_error
            end

            return self
        end

        function s:setoption(name, value)
            state.setoptions[#state.setoptions + 1] = {
                idx = idx,
                family = family,
                name = name,
                value = value
            }

            local err = cfg.setoption_errors and cfg.setoption_errors[name]
            if err then
                return nil, err
            end

            return true
        end

        function s:send(req)
            local peer = assert(state.connect_records[idx], 'send requires a connected socket')
            local meta = parse_dns_request(req)

            state.send_records[idx] = {
                host = peer[1],
                port = peer[2],
                family = family,
                req = req,
                meta = meta
            }

            local err = cfg.send_errors and cfg.send_errors[idx]
            if err then
                return nil, err
            end

            return #req, nil
        end

        function s:recvfrom(n, timeout)
            recv_count = recv_count + 1
            state.now = state.now + (cfg.recv_elapsed or 0)
            state.recv_records[idx] = {
                n = n,
                timeout = timeout,
                family = family,
                count = recv_count
            }

            if cfg.recv_builder then
                return cfg.recv_builder(idx, state, recv_count)
            end

            local entry = cfg.recv_entries and cfg.recv_entries[idx]
            if entry then
                if entry.err then
                    return nil, entry.err
                end

                return entry.data, nil
            end

            return nil, 'timeout'
        end

        return setmetatable(s, {
            __close = function()
                state.close_count = state.close_count + 1
            end
        })
    end

    local socket = {
        udp = function()
            state.udp_calls = state.udp_calls + 1
            if cfg.udp_error then
                return nil, cfg.udp_error
            end

            return make_socket('udp4')
        end,
        udp6 = function()
            state.udp6_calls = state.udp6_calls + 1
            if cfg.udp6_error then
                return nil, cfg.udp6_error
            end

            return make_socket('udp6')
        end,
        is_ipv4_address = is_ipv4,
        is_ipv6_address = is_ipv6,
        is_ip_address = function(host)
            return is_ipv4(host) or is_ipv6(host)
        end
    }

    local file = {
        access = function(path)
            if path == '/etc/resolv.conf' then
                if cfg.resolv_exists == nil then
                    return true
                end

                return cfg.resolv_exists
            end

            if path == '/etc/hosts' then
                if cfg.hosts_exists == nil then
                    return true
                end

                return cfg.hosts_exists
            end

            return true
        end,
        stat = function(path)
            if path == '/etc/resolv.conf' then
                if cfg.resolv_exists == false then
                    return nil, 'not found'
                end

                return {
                    mtime = cfg.resolv_mtime or 1
                }
            end

            if path == '/etc/hosts' then
                if cfg.hosts_exists == false then
                    return nil, 'not found'
                end

                return {
                    mtime = cfg.hosts_mtime or 1
                }
            end

            return {
                mtime = 1
            }
        end
    }

    local function lines_from(list)
        local i = 0

        return function()
            i = i + 1
            return list[i]
        end
    end

    local io_lines = function(path)
        if path == '/etc/hosts' then
            return lines_from(cfg.hosts_lines or {})
        end

        if path == '/etc/resolv.conf' then
            return lines_from(cfg.resolv_lines or {})
        end

        return io.lines(path)
    end

    return {
        socket = socket,
        time = {
            CLOCK_MONOTONIC = 1,
            now = function(clock)
                assert(clock == 1)
                return state.now
            end
        },
        file = file,
        io_lines = io_lines,
        state = state
    }
end

-- Exported constants and type_name mapping.
assert(math.type(dns.TYPE_A) == 'integer')
assert(math.type(dns.TYPE_AAAA) == 'integer')
assert(math.type(dns.TYPE_SRV) == 'integer')
assert(math.type(dns.CLASS_IN) == 'integer')
assert(math.type(dns.SECTION_AN) == 'integer')

assert(dns.type_name(dns.TYPE_A) == 'A')
assert(dns.type_name(dns.TYPE_AAAA) == 'AAAA')
assert(dns.type_name(dns.TYPE_MX) == 'MX')
assert(dns.type_name(65535) == 'unknown')

-- Direct IP queries should short-circuit without network access.
test.run_case_async('dns query direct ip literals', function()
    local answers, err = dns.query('127.0.0.1')
    assert(answers and err == nil)
    assert(#answers == 1 and answers[1].type == dns.TYPE_A and answers[1].address == '127.0.0.1')

    answers, err = dns.query('::1')
    assert(answers and err == nil)
    assert(#answers == 1 and answers[1].type == dns.TYPE_AAAA and answers[1].address == '::1')
end)

-- Input validation for qname.
test.run_case_async('dns query bad name', function()
    local answers, err = dns.query('.bad')
    assert(answers == nil and err == 'bad name')

    local too_long = string.rep('a', 256)
    answers, err = dns.query(too_long)
    assert(answers == nil and err == 'bad name')
end)

-- /etc/hosts should be consulted before DNS queries.
test.run_case_async('dns query hosts first', function()
    with_stubbed_dns(function()
        return make_env({
            hosts_lines = {
                '127.0.0.77 printer printer.local',
                '::1 localhost'
            },
            resolv_lines = {
                'nameserver 1.1.1.1'
            }
        })
    end, function(dns_mod, state)
        local answers, err = dns_mod.query('printer', { type = dns_mod.TYPE_A })
        assert(answers and err == nil)
        assert(#answers == 1)
        assert(answers[1].type == dns_mod.TYPE_A)
        assert(answers[1].address == '127.0.0.77')

        assert(state.udp_calls == 0 and state.udp6_calls == 0, 'hosts hit should not create udp sockets')
    end)
end)

test.run_case_async('dns hosts whitespace and comments', function()
    with_stubbed_dns(function()
        return make_env({
            hosts_lines = {
                '', '   ', '\t', ' \t ', '# comment', '  # indented comment',
                '\t192.0.2.7 printer alias # ignored', '  ::1 printer6',
                '192.0.2.8 printer', '192.0.2.9', 'invalid-address ignored'
            },
            is_ipv4 = socket.is_ipv4_address,
            is_ipv6 = socket.is_ipv6_address
        })
    end, function(dns_mod, state)
        for _, name in ipairs({ 'printer', 'alias' }) do
            local answers, err = dns_mod.query(name)
            assert(answers and answers[1].address == '192.0.2.7', err)
        end

        local answers, err = dns_mod.query('printer6', { type = dns_mod.TYPE_AAAA })
        assert(answers and answers[1].address == '::1', err)
        assert(state.udp_calls == 0 and state.udp6_calls == 0)
    end)
end)

test.run_case_async('dns retries failed hosts index builds', function()
    for _, cached in ipairs({ false, true }) do
        local cfg = { hosts_lines = { '192.0.2.1 printer' }, hosts_mtime = 1 }
        local fail = false
        local reads = 0

        with_stubbed_dns(function()
            local env = make_env(cfg)
            local io_lines = env.io_lines

            env.io_lines = function(path)
                if path == '/etc/hosts' then
                    reads = reads + 1
                    if fail then
                        error('hosts read failed')
                    end
                end

                return io_lines(path)
            end

            return env
        end, function(dns_mod, state)
            if cached then
                assert(dns_mod.query('printer')[1].address == '192.0.2.1')
                cfg.hosts_mtime = 2
            end

            fail = true
            test.expect_error_contains(function()
                dns_mod.query('printer')
            end, 'hosts read failed')

            fail = false
            cfg.hosts_lines = { '192.0.2.2 printer' }

            local answers, err = dns_mod.query('printer')
            assert(answers and answers[1].address == '192.0.2.2', err)
            assert(reads == (cached and 3 or 2))
            assert(dns_mod.query('printer')[1].address == '192.0.2.2')
            assert(reads == (cached and 3 or 2), 'successful index should be cached')
            assert(state.udp_calls == 0 and state.udp6_calls == 0)
        end)
    end
end)

test.run_case_async('dns non-address queries bypass hosts', function()
    local types = {
        dns.TYPE_NS, dns.TYPE_CNAME, dns.TYPE_SOA, dns.TYPE_PTR,
        dns.TYPE_MX, dns.TYPE_TXT, dns.TYPE_SRV, dns.TYPE_SPF
    }

    for _, typ in ipairs(types) do
        local hosts_reads = 0

        with_stubbed_dns(function()
            local env = make_env({
                hosts_lines = { '192.0.2.1 service.example' },
                recv_builder = function(idx, state)
                    return build_error_response(state.send_records[idx].meta, 0)
                end
            })
            local io_lines = env.io_lines

            env.io_lines = function(path)
                if path == '/etc/hosts' then
                    hosts_reads = hosts_reads + 1
                end

                return io_lines(path)
            end

            return env
        end, function(dns_mod, state)
            local answers, err = dns_mod.query('service.example', { type = typ })
            assert(answers and #answers == 0 and err == nil, err)
            assert(state.udp_calls == 1)
            assert(state.send_records[1].meta.qtype == typ)
            assert(hosts_reads == 0, 'non-address queries should not read hosts')
            assert(state.close_count == 1)
        end)
    end
end)

-- nameservers, retry, no_recurse, mark/device and socket family selection.
test.run_case_async('dns query nameserver retry and options', function()
    with_stubbed_dns(function()
        return make_env({
            hosts_lines = {},
            recv_builder = function(idx, state)
                local req_meta = state.send_records[idx].meta

                if idx == 1 then
                    return build_error_response(req_meta, 2)
                end

                return build_a_response(req_meta, '10.0.0.8')
            end
        })
    end, function(dns_mod, state)
        local answers, err = dns_mod.query('svc.example', {
            type = dns_mod.TYPE_A,
            no_recurse = true,
            mark = 66,
            device = 'eth9',
            nameservers = {
                '1.1.1.1',
                { '2001:db8::53', 5300 }
            }
        })

        assert(answers and err == nil, err)
        assert(#answers == 1)
        assert(answers[1].type == dns_mod.TYPE_A)
        assert(answers[1].address == '10.0.0.8')

        assert(state.udp_calls == 1)
        assert(state.udp6_calls == 1)

        assert(state.send_records[1].host == '1.1.1.1' and state.send_records[1].port == 53)
        assert(state.send_records[2].host == '2001:db8::53' and state.send_records[2].port == 5300)

        local first_meta = state.send_records[1].meta
        assert(first_meta.qname == 'svc.example')
        assert(first_meta.qtype == dns_mod.TYPE_A)
        assert(first_meta.qclass == dns_mod.CLASS_IN)
        assert((first_meta.flags & (1 << 8)) == 0, 'no_recurse should clear RD flag')

        assert(#state.setoptions == 4, 'mark+bindtodevice should be set for each attempt')
        assert(state.setoptions[1].name == 'mark' and state.setoptions[1].value == 66)
        assert(state.setoptions[2].name == 'bindtodevice' and state.setoptions[2].value == 'eth9')

        assert(state.close_count == 2, 'to-be-closed sockets should close on each attempt')
    end)
end)

-- resolv.conf search should be applied for short hostnames.
test.run_case_async('dns query applies search domain from resolv.conf', function()
    with_stubbed_dns(function()
        return make_env({
            hosts_lines = {},
            resolv_exists = true,
            resolv_lines = {
                'search lan',
                'nameserver 9.9.9.9'
            },
            recv_builder = function(idx, state)
                return build_a_response(state.send_records[idx].meta, '192.0.2.9')
            end
        })
    end, function(dns_mod, state)
        local answers, err = dns_mod.query('nas')
        assert(answers and err == nil, err)
        assert(#answers == 1 and answers[1].address == '192.0.2.9')

        assert(state.send_records[1].meta.qname == 'nas.lan')
        assert(state.send_records[1].host == '9.9.9.9')
    end)
end)

test.run_case_async('dns resolv.conf directives and comments', function()
    local cases = {
        {
            lines = {
                '# search', '; search', '  # nameserver 192.0.2.99',
                '  ; nameserver 192.0.2.98', 'nameserver 192.0.2.53 # search'
            },
            host = '192.0.2.53', name = 'nas'
        },
        {
            lines = { '', '   ', 'search', 'search   ', 'nameserver', 'nameserver # missing' },
            host = '127.0.0.1', name = 'nas'
        },
        {
            lines = {
                'notsearch wrong.example', 'xnameserver 192.0.2.99',
                'options search bogus', 'nameserver invalid-address',
                'nameserver 192.0.2.53'
            },
            host = '192.0.2.53', name = 'nas'
        },
        {
            lines = { '  search corp.example # comment', '  nameserver 192.0.2.53; search bogus' },
            host = '192.0.2.53', name = 'nas.corp.example'
        },
        {
            lines = {
                'search old.example', '\tsearch\tcorp.example other.example ; ignored',
                '\tnameserver\t2001:db8::53 # comment'
            },
            host = '2001:db8::53', name = 'nas.corp.example', ipv6 = true
        },
        {
            lines = {
                'search corp.example', 'search # missing', 'search ; missing',
                'nameserver 192.0.2.53'
            },
            host = '192.0.2.53', name = 'nas.corp.example'
        }
    }

    for _, case in ipairs(cases) do
        with_stubbed_dns(function()
            return make_env({
                resolv_lines = case.lines,
                recv_builder = function(idx, state)
                    return build_a_response(state.send_records[idx].meta, '192.0.2.9')
                end
            })
        end, function(dns_mod, state)
            local answers, err = dns_mod.query('nas')
            assert(answers and answers[1].address == '192.0.2.9', err)
            assert(state.send_records[1].host == case.host)
            assert(state.send_records[1].meta.qname == case.name)
            assert(state.udp_calls == (case.ipv6 and 0 or 1))
            assert(state.udp6_calls == (case.ipv6 and 1 or 0))
        end)
    end
end)

-- nameserver option validation.
test.run_case_async('dns query nameserver validation', function()
    with_stubbed_dns(function()
        return make_env({
            hosts_lines = {}
        })
    end, function(dns_mod)
        test.expect_error_contains(function()
            dns_mod.query('example.com', {
                nameservers = { 1 }
            })
        end, 'invalid nameservers', 'non-string/table nameserver entry should throw')

        test.expect_error_contains(function()
            dns_mod.query('example.com', {
                nameservers = { 'not-an-ip' }
            })
        end, 'invalid nameserver: not-an-ip', 'invalid nameserver ip should throw')
    end)
end)

-- network send/recv errors should be wrapped with nameserver context.
test.run_case_async('dns query send recv failures', function()
    with_stubbed_dns(function()
        return make_env({
            hosts_lines = {},
            send_errors = {
                [1] = 'boom'
            }
        })
    end, function(dns_mod)
        local answers, err = dns_mod.query('example.com', {
            nameservers = { '8.8.8.8' }
        })

        assert(answers == nil)
        assert(type(err) == 'string' and err:find('send "8.8.8.8:53" fail: boom', 1, true))
    end)

    with_stubbed_dns(function()
        return make_env({
            hosts_lines = {},
            recv_entries = {
                [1] = { err = 'timeout' }
            }
        })
    end, function(dns_mod)
        local answers, err = dns_mod.query('example.com', {
            nameservers = { '8.8.4.4' }
        })

        assert(answers == nil)
        assert(type(err) == 'string' and err:find('recv from "8.8.4.4:53" fail: timeout', 1, true))
    end)
end)

-- parser-level resolver errors and response validation.
test.run_case_async('dns query parser failures', function()
    with_stubbed_dns(function()
        return make_env({
            hosts_lines = {},
            recv_builder = function(idx, state)
                return build_error_response(state.send_records[idx].meta, 3)
            end
        })
    end, function(dns_mod)
        local answers, err = dns_mod.query('missing.example', {
            nameservers = { '1.1.1.1' }
        })

        assert(answers == nil)
        assert(err == 'name error')
    end)

    with_stubbed_dns(function()
        return make_env({
            hosts_lines = {},
            recv_builder = function(idx, state, count)
                if count > 1 then
                    return nil, 'timeout'
                end

                local meta = state.send_records[idx].meta
                local question = encode_name(meta.qname) .. string.pack('>I2I2', meta.qtype, 3)
                return string.pack('>I2I2I2I2I2I2', meta.id, 0x8180, 1, 0, 0, 0) .. question
            end
        })
    end, function(dns_mod)
        local answers, err = dns_mod.query('badclass.example', {
            nameservers = { '1.0.0.1' }
        })

        assert(answers == nil)
        assert(type(err) == 'string' and err:find('timeout', 1, true))
    end)
end)

test.run_case_async('dns ignores unrelated datagrams', function()
    with_stubbed_dns(function()
        return make_env({
            recv_elapsed = 0.1,
            recv_builder = function(idx, state, count)
                local meta = state.send_records[idx].meta
                local reply = {
                    id = meta.id,
                    qname = meta.qname,
                    qtype = meta.qtype,
                    qclass = meta.qclass
                }

                if count == 1 then
                    return ''
                elseif count == 2 then
                    reply.id = (meta.id + 1) % 65536
                elseif count == 3 then
                    reply.qname = 'other.example'
                elseif count == 4 then
                    reply.qtype = dns.TYPE_AAAA
                elseif count == 5 then
                    reply.qclass = 3
                elseif count == 6 then
                    reply.qname = 'other.example'
                    return build_error_response(reply, 3)
                elseif count == 7 then
                    reply.qname = 'other.example'
                    return build_a_response(reply, '192.0.2.99', 0x8380)
                elseif count == 8 then
                    return build_a_response(reply, '192.0.2.99', 0x8980)
                elseif count == 9 then
                    return build_a_response(reply, '192.0.2.99', 0x0100)
                else
                    assert(count == 10, 'resolver must accept the matching response')
                    reply.qname = meta.qname:upper()
                    return build_a_response(reply, '192.0.2.8')
                end

                return build_a_response(reply, '192.0.2.99')
            end
        })
    end, function(dns_mod, state)
        local answers, err = dns_mod.query('service.example.', {
            nameservers = { '192.0.2.53' }
        })
        assert(answers and answers[1].address == '192.0.2.8', err)
        assert(state.udp_calls == 1 and state.close_count == 1)
        assert(state.connect_records[1][1] == '192.0.2.53')
        assert(state.connect_records[1][2] == 53)
        assert(state.recv_records[1].count == 10)
        assert(state.recv_records[1].timeout < 5)
    end)
end)

test.run_case_async('dns unrelated datagrams do not reset deadline', function()
    with_stubbed_dns(function()
        return make_env({
            recv_elapsed = 2,
            recv_builder = function(idx, state, count)
                assert(count <= 3, 'unrelated packets must not extend the deadline')
                assert(state.recv_records[idx].timeout == 7 - count * 2)
                return ''
            end
        })
    end, function(dns_mod, state)
        local answers, err = dns_mod.query('service.example')
        assert(answers == nil and err:find('timeout', 1, true))
        assert(state.recv_records[1].count == 3)
        assert(state.close_count == 1)
    end)
end)

test.run_case_async('dns socket creation failures', function()
    for _, ipv6 in ipairs({ false, true }) do
        with_stubbed_dns(function()
            return make_env({
                udp_error = not ipv6 and 'Too many open files' or nil,
                udp6_error = ipv6 and 'Address family not supported' or nil
            })
        end, function(dns_mod, state)
            local answers, err = dns_mod.query('service.example', {
                nameservers = { ipv6 and '::1' or '127.0.0.1' },
                mark = 1,
                device = 'lo'
            })

            assert(answers == nil)
            assert(err == (ipv6 and 'Address family not supported' or 'Too many open files'))
            assert(state.udp_calls == (ipv6 and 0 or 1))
            assert(state.udp6_calls == (ipv6 and 1 or 0))
            assert(#state.setoptions == 0 and #state.connect_records == 0)
            assert(#state.send_records == 0 and state.close_count == 0)
        end)
    end
end)

test.run_case_async('dns socket option failures', function()
    for _, ipv6 in ipairs({ false, true }) do
        for _, option in ipairs({ 'mark', 'bindtodevice' }) do
            local expected_err = option == 'mark' and 'Operation not permitted' or 'No such device'

            with_stubbed_dns(function()
                return make_env({ setoption_errors = { [option] = expected_err } })
            end, function(dns_mod, state)
                local answers, err = dns_mod.query('service.example', {
                    nameservers = { ipv6 and '::1' or '127.0.0.1', '192.0.2.53' },
                    mark = 0,
                    device = 'lo'
                })

                assert(answers == nil and err == expected_err)
                assert(state.udp_calls == (ipv6 and 0 or 1))
                assert(state.udp6_calls == (ipv6 and 1 or 0))
                assert(#state.setoptions == (option == 'mark' and 1 or 2))
                assert(#state.connect_records == 0 and #state.send_records == 0)
                assert(#state.recv_records == 0 and state.close_count == 1)
            end)
        end
    end
end)

test.run_case_async('dns connect failure', function()
    with_stubbed_dns(function()
        return make_env({ connect_error = 'Network is unreachable' })
    end, function(dns_mod, state)
        local answers, err = dns_mod.query('service.example')
        assert(answers == nil and err:find('connect', 1, true))
        assert(err:find('Network is unreachable', 1, true))
        assert(#state.send_records == 0 and state.close_count == 1)
    end)
end)

test.run_case_async('dns random source failure', function()
    with_stubbed_dns(function()
        local env = make_env()
        env.dns = {
            transaction_id = function()
                return nil, 'random source unavailable'
            end
        }

        return env
    end, function(dns_mod, state)
        local answers, err = dns_mod.query('service.example')
        assert(answers == nil and err == 'random source unavailable')
        assert(state.udp_calls == 0 and state.udp6_calls == 0)
    end)
end)

test.run_case_async('dns question label boundaries and compression', function()
    local parser = require 'eco.internal.dns'
    local req = string.pack('>I2I2I2I2I2I2', 123, 0x0100, 1, 0, 0, 0)
        .. encode_name('a.b') .. string.pack('>I2I2', dns.TYPE_A, dns.CLASS_IN)
    local header = string.pack('>I2I2I2I2I2I2', 123, 0x8180, 1, 0, 0, 0)
    local tail = string.pack('>I2I2', dns.TYPE_A, dns.CLASS_IN)

    for _, name in ipairs({ '\3a.b\0', '\3a\0b\0', '\192\12', '\192\255', '\192', '\64' }) do
        local answers, err = parser.parse_response(header .. name .. tail, req)
        assert(answers == nil and err == nil, 'unmatchable questions must be ignored')
    end

    -- The question's root label points to the zero byte in the transaction ID.
    local compressed_req = string.pack('>I2I2I2I2I2I2', 0, 0x0100, 1, 0, 0, 0) .. '\0' .. tail
    local compressed_reply = string.pack('>I2I2I2I2I2I2', 0, 0x8000, 1, 0, 0, 0) .. '\192\0' .. tail
    local answers, err = parser.parse_response(compressed_reply, compressed_req)
    assert(answers and #answers == 0 and err == nil)
end)

test.run_case_async('dns shared name parser preserves record fields', function()
    local parser = require 'eco.internal.dns'
    local question = encode_name('service.example') .. string.pack('>I2I2', dns.TYPE_A, dns.CLASS_IN)
    local req = string.pack('>I2I2I2I2I2I2', 123, 0x0100, 1, 0, 0, 0) .. question
    local records = {
        { dns.TYPE_CNAME, '\192\12', { cname = 'service.example' } },
        { dns.TYPE_NS, '\0', { nsdname = '' } },
        { dns.TYPE_PTR, '\192\12', { ptrdname = 'service.example' } },
        { dns.TYPE_MX, string.pack('>I2', 10) .. '\192\12',
            { preference = 10, exchange = 'service.example' } },
        { dns.TYPE_SRV, string.pack('>I2I2I2', 1, 2, 443) .. '\192\12',
            { priority = 1, weight = 2, port = 443, target = 'service.example' } },
        { dns.TYPE_SOA, '\192\12\192\12' .. string.pack('>I4I4I4I4I4', 1, 2, 3, 4, 5),
            { mname = 'service.example', rname = 'service.example', serial = 1,
                refresh = 2, retry = 3, expire = 4, minimum = 5 } }
    }
    local response = string.pack('>I2I2I2I2I2I2', 123, 0x8180, 1, #records, 0, 0) .. question

    for _, record in ipairs(records) do
        response = response .. '\192\12'
            .. string.pack('>I2I2I4I2', record[1], dns.CLASS_IN, 30, #record[2]) .. record[2]
    end

    local answers, err = parser.parse_response(response, req)
    assert(answers and #answers == #records, err)

    for i, record in ipairs(records) do
        assert(answers[i].name == 'service.example' and answers[i].type == record[1])
        for field, value in pairs(record[3]) do
            assert(answers[i][field] == value, field)
        end
    end
end)

test.run_case_async('dns unsigned 32-bit record fields', function()
    local parser = require 'eco.internal.dns'
    local question = encode_name('service.example') .. string.pack('>I2I2', dns.TYPE_SOA, dns.CLASS_IN)
    local req = string.pack('>I2I2I2I2I2I2', 123, 0x0100, 1, 0, 0, 0) .. question
    local header = string.pack('>I2I2I2I2I2I2', 123, 0x8180, 1, 1, 0, 0) .. question

    for _, value in ipairs({ 0, 0x7fffffff, 0x80000000, 0x89abcdef, 0xffffffff }) do
        local rdata = '\192\12\192\12' .. string.pack('>I4I4I4I4I4', value, value, value, value, value)
        local response = header .. '\192\12'
            .. string.pack('>I2I2I4I2', dns.TYPE_SOA, dns.CLASS_IN, value, #rdata) .. rdata
        local answers, err = parser.parse_response(response, req)
        assert(answers and #answers == 1, err)

        for _, field in ipairs({ 'ttl', 'serial', 'refresh', 'retry', 'expire', 'minimum' }) do
            assert(answers[1][field] == value, field)
        end
    end
end)

for _, host in ipairs({ '127.0.0.1', '::1' }) do
    test.run_case_async('dns rejects foreign UDP source ' .. host, function()
        local server<close> = assert(socket.listen_udp(host, 0, { ipv6 = host == '::1' }))
        local rogue<close> = assert(socket.listen_udp(host, 0, { ipv6 = host == '::1' }))
        local port = assert(server:getsockname()).port
        local other<close> = host == '127.0.0.1' and assert(socket.listen_udp('127.0.0.2', port))
        local done = false

        eco.run(function()
            local req, peer = server:recvfrom(512, 1)
            assert(req, peer)
            local meta = parse_dns_request(req)
            if other then
                assert(other:sendto(build_a_response(meta, '192.0.2.98'), peer.ipaddr, peer.port))
            end

            assert(rogue:sendto(build_a_response(meta, '192.0.2.99'), peer.ipaddr, peer.port))
            eco.sleep(0.02)
            assert(server:sendto(build_a_response(meta, '192.0.2.8'), peer.ipaddr, peer.port))
            done = true
        end)

        local answers, err = dns.query('dns-review.invalid', { nameservers = {{ host, port }} })
        assert(answers and answers[1].address == '192.0.2.8', err)
        assert(done, 'query must wait for the configured server')
    end)
end

print('dns tests passed')
