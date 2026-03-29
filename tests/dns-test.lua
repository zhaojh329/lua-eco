#!/usr/bin/env eco

local test = require 'test'
local dns = require 'eco.dns'

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
        'eco.internal.file'
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

        function s:setoption(name, value)
            state.setoptions[#state.setoptions + 1] = {
                idx = idx,
                family = family,
                name = name,
                value = value
            }
            return true
        end

        function s:sendto(req, host, port)
            local meta = parse_dns_request(req)

            state.send_records[idx] = {
                host = host,
                port = port,
                family = family,
                req = req,
                meta = meta
            }

            local err = cfg.sendto_errors and cfg.sendto_errors[idx]
            if err then
                return nil, err
            end

            return #req, nil
        end

        function s:recv(n, timeout)
            state.recv_records[idx] = {
                n = n,
                timeout = timeout,
                family = family
            }

            if cfg.recv_builder then
                return cfg.recv_builder(idx, state)
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
            return make_socket('udp4')
        end,
        udp6 = function()
            state.udp6_calls = state.udp6_calls + 1
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

-- nameservers, retry, no_recurse, mark/device and socket family selection.
test.run_case_async('dns query nameserver retry and options', function()
    with_stubbed_dns(function()
        return make_env({
            hosts_lines = {},
            recv_builder = function(idx, state)
                local req_meta = state.send_records[idx].meta

                if idx == 1 then
                    -- Force parse failure on first nameserver to trigger retry.
                    return build_a_response({
                        id = (req_meta.id + 1) % 65536,
                        qname = req_meta.qname,
                        qtype = req_meta.qtype,
                        qclass = req_meta.qclass
                    }, '10.0.0.1')
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
            sendto_errors = {
                [1] = 'boom'
            }
        })
    end, function(dns_mod)
        local answers, err = dns_mod.query('example.com', {
            nameservers = { '8.8.8.8' }
        })

        assert(answers == nil)
        assert(type(err) == 'string' and err:find('sendto "8.8.8.8:53" fail: boom', 1, true))
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
            recv_builder = function(idx, state)
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
        assert(type(err) == 'string' and err:find('unknown query class', 1, true))
    end)
end)

print('dns tests passed')
