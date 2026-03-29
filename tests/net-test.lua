#!/usr/bin/env eco

local test = require 'test'

local SENTINEL = {}

local function restore_modules(saved)
    for name, value in pairs(saved) do
        if value == SENTINEL then
            package.loaded[name] = nil
        else
            package.loaded[name] = value
        end
    end
end

local function with_stubbed_net(factory, fn)
    local names = {
        'eco.net',
        'eco.socket',
        'eco.packet',
        'eco.time',
        'eco.dns'
    }

    local saved = {}

    for _, name in ipairs(names) do
        if package.loaded[name] == nil then
            saved[name] = SENTINEL
        else
            saved[name] = package.loaded[name]
        end
    end

    local env = factory()

    package.loaded['eco.socket'] = env.socket
    package.loaded['eco.packet'] = env.packet
    package.loaded['eco.time'] = env.time
    package.loaded['eco.dns'] = env.dns
    package.loaded['eco.net'] = nil

    local ok, mod_or_err = pcall(require, 'eco.net')
    if not ok then
        restore_modules(saved)
        error(mod_or_err)
    end

    local net = mod_or_err

    local run_ok, run_err = pcall(fn, net, env.state)

    restore_modules(saved)

    assert(run_ok, run_err)
end

local function make_env(cfg)
    cfg = cfg or {}

    local state = {
        dns_queries = {},
        setoptions = {},
        sent_packets = {},
        recv_calls = {},
        packet_icmp_calls = {},
        packet_icmp6_calls = {},
        weak_sockets = setmetatable({}, { __mode = 'v' })
    }

    local now_index = 0

    local function now()
        now_index = now_index + 1

        if cfg.time_values and cfg.time_values[now_index] ~= nil then
            return cfg.time_values[now_index]
        end

        return now_index * 0.01
    end

    local function make_socket(kind)
        local s = {}

        state.socket_count = (state.socket_count or 0) + 1
        state.weak_sockets[state.socket_count] = s

        function s:setoption(name, value)
            state.setoptions[#state.setoptions + 1] = {
                name = name,
                value = value
            }

            return true
        end

        function s:bind(host, id)
            state.bind_host = host
            state.bind_id = id
            state.bind_kind = kind
            return true
        end

        function s:sendto(pkt, ipaddr, port)
            state.sent_packets[#state.sent_packets + 1] = {
                pkt = pkt,
                ipaddr = ipaddr,
                port = port,
                kind = kind
            }

            if cfg.sendto_err then
                return nil, cfg.sendto_err
            end

            return #tostring(pkt), nil
        end

        function s:recvfrom(n, timeout)
            state.recv_calls[#state.recv_calls + 1] = {
                n = n,
                timeout = timeout,
                kind = kind
            }

            if cfg.recv_err then
                return nil, cfg.recv_err
            end

            return cfg.recv_data or (kind .. '-reply'), {
                ipaddr = cfg.peer_ipaddr or (kind == 'icmp6' and '::1' or '127.0.0.1')
            }
        end

        return s
    end

    local socket = {
        ICMP_ECHOREPLY = 0,
        ICMP_ECHO = 8,
        ICMPV6_ECHO_REPLY = 129,
        ICMPV6_ECHO_REQUEST = 128
    }

    function socket.is_ipv4_address(host)
        if cfg.is_ipv4 then
            return cfg.is_ipv4(host)
        end

        return host == '1.1.1.1'
    end

    function socket.is_ipv6_address(host)
        if cfg.is_ipv6 then
            return cfg.is_ipv6(host)
        end

        return host == '::1'
    end

    function socket.icmp()
        state.icmp_called = (state.icmp_called or 0) + 1

        if cfg.icmp_err then
            return nil, cfg.icmp_err
        end

        return make_socket('icmp')
    end

    function socket.icmp6()
        state.icmp6_called = (state.icmp6_called or 0) + 1

        if cfg.icmp6_err then
            return nil, cfg.icmp6_err
        end

        return make_socket('icmp6')
    end

    local packet = {}

    function packet.icmp(typ, code, csum, seq, data)
        state.packet_icmp_calls[#state.packet_icmp_calls + 1] = {
            typ = typ,
            code = code,
            csum = csum,
            seq = seq,
            data = data
        }

        return cfg.icmp_packet or ('icmp-pkt-' .. tostring(seq) .. '-' .. tostring(data))
    end

    function packet.icmp6(typ, code, csum, seq, data)
        state.packet_icmp6_calls[#state.packet_icmp6_calls + 1] = {
            typ = typ,
            code = code,
            csum = csum,
            seq = seq,
            data = data
        }

        return cfg.icmp6_packet or ('icmp6-pkt-' .. tostring(seq) .. '-' .. tostring(data))
    end

    function packet.from_icmp(data)
        state.from_icmp_data = data

        if cfg.from_icmp then
            return cfg.from_icmp(state, data)
        end

        return {
            type = socket.ICMP_ECHOREPLY,
            id = state.bind_id
        }
    end

    function packet.from_icmp6(data)
        state.from_icmp6_data = data

        if cfg.from_icmp6 then
            return cfg.from_icmp6(state, data)
        end

        return {
            type = socket.ICMPV6_ECHO_REPLY,
            id = state.bind_id
        }
    end

    local dns = {
        TYPE_A = 1,
        TYPE_AAAA = 28
    }

    function dns.query(host, opts)
        state.dns_queries[#state.dns_queries + 1] = {
            host = host,
            opts = opts
        }

        if cfg.dns_err then
            return nil, cfg.dns_err
        end

        return cfg.dns_answers or {}, nil
    end

    return {
        socket = socket,
        packet = packet,
        time = { now = now },
        dns = dns,
        state = state
    }
end

local function should_skip_smoke_error(err)
    if type(err) ~= 'string' then
        return false
    end

    local s = err:lower()

    return s:find('operation not permitted', 1, true)
        or s:find('permission denied', 1, true)
        or s:find('protocol not supported', 1, true)
        or s:find('address family not supported', 1, true)
        or s:find('socket type not supported', 1, true)
        or s:find('network is unreachable', 1, true)
        or s:find('no route to host', 1, true)
        or s:find('timeout', 1, true)
end

-- Real API smoke tests: validate end-to-end calls when runtime environment allows ICMP.
test.run_case_async('net smoke ping localhost ipv4', function()
    local net = require 'eco.net'

    local rtt, err = net.ping('127.0.0.1', {
        timeout = 0.5,
        data = 'smoke-v4'
    })

    if not rtt then
        if should_skip_smoke_error(err) then
            print('skip net smoke ipv4:', err)
            return
        end

        assert(rtt, err)
    end

    assert(type(rtt) == 'number' and rtt >= 0)
end)

test.run_case_async('net smoke ping localhost ipv6', function()
    local net = require 'eco.net'

    local rtt, err = net.ping6('::1', {
        timeout = 0.5,
        data = 'smoke-v6'
    })

    if not rtt then
        if should_skip_smoke_error(err) then
            print('skip net smoke ipv6:', err)
            return
        end

        assert(rtt, err)
    end

    assert(type(rtt) == 'number' and rtt >= 0)
end)

test.run_case_sync('net ping ipv4 success default opts', function()
    with_stubbed_net(function()
        return make_env({
            is_ipv4 = function(host)
                return host == '203.0.113.5'
            end,
            time_values = { 10.0, 10.125 },
            recv_data = 'icmp-data'
        })
    end, function(net, state)
        local rtt, err = net.ping('203.0.113.5')
        assert(err == nil, err)
        assert(type(rtt) == 'number' and math.abs(rtt - 0.125) < 1e-9)

        assert((state.icmp_called or 0) == 1)
        assert((state.icmp6_called or 0) == 0)
        assert(#state.dns_queries == 0, 'ip input should bypass dns')
        assert(state.bind_host == nil)
        assert(math.type(state.bind_id) == 'integer' and state.bind_id >= 0 and state.bind_id <= 65535)

        assert(#state.packet_icmp_calls == 1)
        assert(state.packet_icmp_calls[1].typ == 8)
        assert(state.packet_icmp_calls[1].seq == 1)
        assert(state.packet_icmp_calls[1].data == 'hello', 'default payload should be hello')

        assert(#state.sent_packets == 1)
        assert(state.sent_packets[1].ipaddr == '203.0.113.5')
        assert(state.sent_packets[1].port == 0)

        assert(#state.recv_calls == 1)
        assert(state.recv_calls[1].timeout == 5.0, 'default timeout should be 5.0')
    end)
end)

test.run_case_sync('net ping hostname resolves A and forwards opts', function()
    with_stubbed_net(function()
        return make_env({
            is_ipv4 = function()
                return false
            end,
            dns_answers = {
                { type = 99, address = '198.51.100.8' },
                { type = 1, address = '198.51.100.9' }
            },
            time_values = { 20.0, 20.02 },
            recv_data = 'icmp-data'
        })
    end, function(net, state)
        local opts = {
            timeout = 0.7,
            data = 'abc',
            mark = 123,
            device = 'eth0',
            nameservers = { '9.9.9.9', '8.8.8.8' }
        }

        local rtt, err = net.ping('example.test', opts)
        assert(err == nil, err)
        assert(type(rtt) == 'number' and math.abs(rtt - 0.02) < 1e-9)

        assert(#state.dns_queries == 1)
        assert(state.dns_queries[1].host == 'example.test')
        assert(state.dns_queries[1].opts.type == 1)
        assert(state.dns_queries[1].opts.mark == 123)
        assert(state.dns_queries[1].opts.device == 'eth0')
        assert(state.dns_queries[1].opts.nameservers[1] == '9.9.9.9')

        assert(#state.setoptions == 2)
        assert(state.setoptions[1].name == 'bindtodevice' and state.setoptions[1].value == 'eth0')
        assert(state.setoptions[2].name == 'mark' and state.setoptions[2].value == 123)

        assert(#state.packet_icmp_calls == 1)
        assert(state.packet_icmp_calls[1].data == 'abc')

        assert(#state.sent_packets == 1)
        assert(state.sent_packets[1].ipaddr == '198.51.100.9')

        assert(#state.recv_calls == 1)
        assert(state.recv_calls[1].timeout == 0.7)
    end)
end)

test.run_case_sync('net ping failure paths', function()
    with_stubbed_net(function()
        return make_env({
            is_ipv4 = function()
                return false
            end,
            dns_err = 'nxdomain'
        })
    end, function(net)
        local rtt, err = net.ping('bad.example')
        assert(rtt == nil)
        assert(err == 'resolve "bad.example" fail: nxdomain')
    end)

    with_stubbed_net(function()
        return make_env({
            is_ipv4 = function()
                return false
            end,
            dns_answers = {
                { type = 28, address = '::1' }
            }
        })
    end, function(net)
        local rtt, err = net.ping('only-v6.example')
        assert(rtt == nil)
        assert(err == 'resolve "only-v6.example" fail: not found')
    end)

    with_stubbed_net(function()
        return make_env({
            is_ipv4 = function(host)
                return host == '203.0.113.5'
            end,
            icmp_err = 'permission denied'
        })
    end, function(net)
        local rtt, err = net.ping('203.0.113.5')
        assert(rtt == nil and err == 'permission denied')
    end)

    with_stubbed_net(function()
        return make_env({
            is_ipv4 = function(host)
                return host == '203.0.113.5'
            end,
            sendto_err = 'send failed'
        })
    end, function(net)
        local rtt, err = net.ping('203.0.113.5')
        assert(rtt == nil and err == 'send failed')
    end)

    with_stubbed_net(function()
        return make_env({
            is_ipv4 = function(host)
                return host == '203.0.113.5'
            end,
            recv_err = 'timeout'
        })
    end, function(net)
        local rtt, err = net.ping('203.0.113.5')
        assert(rtt == nil and err == 'timeout')
    end)
end)

test.run_case_sync('net ping reply validation', function()
    with_stubbed_net(function()
        return make_env({
            is_ipv4 = function(host)
                return host == '203.0.113.5'
            end,
            from_icmp = function(state)
                return {
                    type = 3,
                    id = state.bind_id
                }
            end
        })
    end, function(net)
        local rtt, err = net.ping('203.0.113.5')
        assert(rtt == nil)
        assert(err == 'unexpected type ICMP 3')
    end)

    with_stubbed_net(function()
        return make_env({
            is_ipv4 = function(host)
                return host == '203.0.113.5'
            end,
            from_icmp = function(state)
                return {
                    type = 0,
                    id = (state.bind_id + 1) % 65536
                }
            end
        })
    end, function(net)
        local rtt, err = net.ping('203.0.113.5')
        assert(rtt == nil)
        assert(type(err) == 'string' and err:find('unexpected icmp id:', 1, true))
    end)
end)

test.run_case_sync('net ping6 hostname resolves AAAA and uses icmp6 path', function()
    with_stubbed_net(function()
        return make_env({
            is_ipv6 = function()
                return false
            end,
            dns_answers = {
                { type = 1, address = '203.0.113.7' },
                { type = 28, address = '2001:db8::7' }
            },
            time_values = { 30.0, 30.05 },
            recv_data = 'icmp6-data'
        })
    end, function(net, state)
        local rtt, err = net.ping6('example6.test', {
            timeout = 1.2,
            data = 'v6data',
            mark = 66,
            device = 'eth1'
        })

        assert(err == nil, err)
        assert(type(rtt) == 'number' and math.abs(rtt - 0.05) < 1e-9)

        assert((state.icmp_called or 0) == 0)
        assert((state.icmp6_called or 0) == 1)

        assert(#state.dns_queries == 1)
        assert(state.dns_queries[1].opts.type == 28)

        assert(#state.packet_icmp6_calls == 1)
        assert(state.packet_icmp6_calls[1].typ == 128)
        assert(state.packet_icmp6_calls[1].data == 'v6data')

        assert(state.sent_packets[1].ipaddr == '2001:db8::7')
        assert(state.recv_calls[1].timeout == 1.2)

        assert(state.from_icmp6_data == 'icmp6-data')
    end)
end)

-- GC regression: temporary sockets created per ping should be collectable.
do
    local weak_ref
    local created

    test.run_case_sync('net temporary socket gc collectable', function()
        with_stubbed_net(function()
            return make_env({
                is_ipv4 = function(host)
                    return host == '203.0.113.5'
                end
            })
        end, function(net, state)
            for _ = 1, 200 do
                local rtt, err = net.ping('203.0.113.5', { timeout = 0.01 })
                assert(type(rtt) == 'number' and err == nil)
            end

            weak_ref = state.weak_sockets
            created = state.socket_count
        end)
    end)

    test.full_gc()

    for i = 1, created do
        assert(weak_ref[i] == nil, 'ping socket should be collectable after each call')
    end
end

-- Memory leak regression: equal ping bursts should show plateau behavior.
do
    local function burst(n)
        with_stubbed_net(function()
            return make_env({
                is_ipv4 = function(host)
                    return host == '203.0.113.5'
                end,
                time_values = { 1.0, 1.0001 }
            })
        end, function(net)
            for _ = 1, n do
                local rtt, err = net.ping('203.0.113.5', { timeout = 0.01, data = 'x' })
                assert(type(rtt) == 'number' and err == nil)
            end
        end)
    end

    local base_mem_kb = test.lua_mem_kb()

    burst(3000)
    local after_first_kb = test.lua_mem_kb()

    burst(3000)
    local after_second_kb = test.lua_mem_kb()

    local growth_first_kb = after_first_kb - base_mem_kb
    local growth_second_kb = after_second_kb - after_first_kb
    local plateau_limit_kb = math.max(128, growth_first_kb * 0.35)

    assert(growth_first_kb < 8192,
           string.format('unexpectedly large initial net memory growth: %.2f KB', growth_first_kb))

    assert(growth_second_kb <= plateau_limit_kb,
           string.format('net memory keeps growing across equal bursts: first %.2f KB, second %.2f KB (limit %.2f KB)',
                         growth_first_kb, growth_second_kb, plateau_limit_kb))
end

print('net tests passed')
