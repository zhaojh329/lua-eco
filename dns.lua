-- SPDX-License-Identifier: MIT
-- Author: Jianhui Zhao <zhaojh329@gmail.com>

-- Referenced from https://github.com/openresty/lua-resty-dns/blob/master/lib/resty/dns/resolver.lua

local socket = require 'eco.socket'

local M = {
    TYPE_A      = 1,
    TYPE_NS     = 2,
    TYPE_CNAME  = 5,
    TYPE_SOA    = 6,
    TYPE_PTR    = 12,
    TYPE_MX     = 15,
    TYPE_TXT    = 16,
    TYPE_AAAA   = 28,
    TYPE_SRV    = 33,
    TYPE_SPF    = 99,
    CLASS_IN    = 1,
    SECTION_AN  = 1,
    SECTION_NS  = 2,
    SECTION_AR  = 3
}

local resolver_errstrs = {
    'format error',     -- 1
    'server failure',   -- 2
    'name error',       -- 3
    'not implemented',  -- 4
    'refused',          -- 5
}

local soa_int32_fields = { 'serial', 'refresh', 'retry', 'expire', 'minimum' }

local transaction_id_init

local function parse_resolvconf()
    local nameservers = {}
    local conf = {}

    for line in io.lines('/etc/resolv.conf') do
        if line:match('search') then
            local search = line:match('search%s+(.+)')
            if not search:match('%.') then
                conf.search = search
            end
        elseif line:match('nameserver') then
            local nameserver = line:match('nameserver%s+(.+)')
            if nameserver then
                if socket.is_ip_address(nameserver) then
                    nameservers[#nameservers + 1] = { nameserver, 53, socket.is_ipv6_address(nameserver) }
                end
            end
        end
    end

    conf.nameservers = nameservers

    return conf
end

local function get_next_transaction_id()
    if not transaction_id_init then
        transaction_id_init = math.random(0, 65535)
    else
        transaction_id_init = transaction_id_init % 65535 + 1
    end

    return transaction_id_init
end

local function build_request(qname, id, opts)
    local flags = 0

    if not opts.no_recurse then
        flags = flags | 1 << 8
    end

    local nqs = 1
    local nan = 0
    local nns = 0
    local nar = 0

    local name = qname:gsub('([^.]+)%.?', function(s)
        return string.char(#s) .. s
    end)

    return string.pack('>I2I2I2I2I2I2zI2I2',
        id, flags, nqs, nan, nns, nar, name, opts.type or M.TYPE_A, M.CLASS_IN)
end

local function decode_name(buf, pos)
    local labels = {}
    local nptrs = 0
    local p = pos

    while nptrs < 128 do
        local fst = string.byte(buf, p)

        if not fst then
            return nil, 'truncated';
        end

        if fst == 0 then
            if nptrs == 0 then
                pos = pos + 1
            end
            break
        end

        if fst & 0xc0 ~= 0 then
            -- being a pointer
            if nptrs == 0 then
                pos = pos + 2
            end

            nptrs = nptrs + 1

            local snd = string.byte(buf, p + 1)
            if not snd then
                return nil, 'truncated'
            end

            p = ((fst & 0x3f) << 8) + snd + 1
        else
            -- being a label
            local label = buf:sub(p + 1, p + fst)
            labels[#labels + 1] = label

            p = p + fst + 1

            if nptrs == 0 then
                pos = p
            end
        end
    end

    return table.concat(labels, '.'), pos
end

local function parse_section(answers, section, buf, start_pos, size)
    local pos = start_pos

    for _ = 1, size do
        local name
        name, pos = decode_name(buf, pos)
        if not name then
            return nil, pos
        end

        local typ, class, ttl, len = string.unpack('>I2I2I4I2', buf:sub(pos))

        local ans = {
            section = section,
            type = typ,
            class = class,
            ttl = ttl,
            name = name
        }

        answers[#answers + 1] = ans

        pos = pos + 10

        if typ == M.TYPE_A then

            if len ~= 4 then
                return nil, 'bad A record value length: ' .. len
            end

            local addr_bytes = { string.byte(buf, pos, pos + 3) }
            local addr = table.concat(addr_bytes, '.')

            ans.address = addr

            pos = pos + 4

        elseif typ == M.TYPE_CNAME then

            local cname, p = decode_name(buf, pos)
            if not cname then
                return nil, pos
            end

            if p - pos ~= len then
                return nil, string.format('bad cname record length: %d ~= %d', p - pos, len)
            end

            pos = p

            ans.cname = cname

        elseif typ == M.TYPE_AAAA then

            if len ~= 16 then
                return nil, 'bad AAAA record value length: ' .. len
            end

            local addr_bytes = { string.byte(buf, pos, pos + 15) }
            local flds = {}
            for i = 1, 16, 2 do
                local a = addr_bytes[i]
                local b = addr_bytes[i + 1]
                if a == 0 then
                    flds[#flds + 1] = string.format('%x', b)
                else
                    flds[#flds + 1] = string.format('%x%02x', a, b)
                end
            end

            -- we do not compress the IPv6 addresses by default
            --  due to performance considerations

            ans.address = table.concat(flds, ':')

            pos = pos + 16

        elseif typ == M.TYPE_MX then

            if len < 3 then
                return nil, 'bad MX record value length: ' .. len
            end

            ans.preference = string.unpack('>I2', buf:sub(pos))

            local host, p = decode_name(buf, pos + 2)
            if not host then
                return nil, pos
            end

            if p - pos ~= len then
                return nil, string.format('bad cname record length: %d ~= %d', p - pos, len)
            end

            ans.exchange = host

            pos = p

        elseif typ == M.TYPE_SRV then
            if len < 7 then
                return nil, 'bad SRV record value length: ' .. len
            end

            ans.priority, ans.weight, ans.port = string.unpack('>I2I2I2', buf:sub(pos))

            local name, p = decode_name(buf, pos + 6)
            if not name then
                return nil, pos
            end

            if p - pos ~= len then
                return nil, string.format('bad srv record length: %d ~= %d', p - pos, len)
            end

            ans.target = name

            pos = p

        elseif typ == M.TYPE_NS then
            local name, p = decode_name(buf, pos)
            if not name then
                return nil, pos
            end

            if p - pos ~= len then
                return nil, string.format('bad cname record length: %d ~= %d', p - pos, len)
            end

            pos = p

            ans.nsdname = name

        elseif typ == M.TYPE_TXT or typ == M.TYPE_SPF then
            local key = typ == M.TYPE_TXT and 'txt' or 'spf'

            local slen = string.byte(buf, pos)
            if slen + 1 > len then
                -- truncate the over-run TXT record data
                slen = len
            end

            local val = buf:sub(pos + 1, pos + slen)
            local last = pos + len
            pos = pos + slen + 1

            if pos < last then
                -- more strings to be processed
                -- this code path is usually cold, so we do not
                -- merge the following loop on this code path
                -- with the processing logic above.

                val = {val}
                local idx = 2
                repeat
                    slen = string.byte(buf, pos)
                    if pos + slen + 1 > last then
                        -- truncate the over-run TXT record data
                        slen = last - pos - 1
                    end

                    val[idx] = buf:sub(pos + 1, pos + slen)
                    idx = idx + 1
                    pos = pos + slen + 1

                until pos >= last
            end

            ans[key] = val

        elseif typ == M.TYPE_PTR then
            local name, p = decode_name(buf, pos)
            if not name then
                return nil, pos
            end

            if p - pos ~= len then
                return nil, string.format('bad cname record length: %d ~= %d', p - pos, len)
            end

            pos = p

            ans.ptrdname = name

        elseif typ == M.TYPE_SOA then
            local name, p = decode_name(buf, pos)
            if not name then
                return nil, pos
            end
            ans.mname = name

            pos = p
            name, p = decode_name(buf, pos)
            if not name then
                return nil, pos
            end
            ans.rname = name

            for _, field in ipairs(soa_int32_fields) do
                ans[field] = string.unpack('>I4', buf:sub(p))
                p = p + 4
            end

            pos = p

        else
            -- for unknown types, just forward the raw value
            ans.rdata = buf:sub(pos, pos + len - 1)
            pos = pos + len
        end
    end

    return pos
end

local function parse_response(buf, id)
    local n = #buf
    if n < 12 then
        return nil, 'truncated';
    end

    -- header layout: ident flags nqs nan nns nar
    local ans_id, flags, nqs, nan = string.unpack('>I2I2I2I2', buf)

    if ans_id ~= id then
        return nil, 'id mismatch'
    end

    if flags & 0x8000 == 0 then
        return nil, 'bad QR flag in the DNS response'
    end

    if flags & 0x200 ~= 0 then
        return nil, 'truncated'
    end

    local code = flags & 0xf

    if nqs ~= 1 then
        return nil, string.format('bad number of questions in DNS response: %d', nqs)
    end

    -- skip the question part
    local ans_qname, pos = decode_name(buf, 13)
    if not ans_qname then
        return nil, pos
    end

    if pos + 3 + nan * 12 > n then
        return nil, 'truncated';
    end

    local qclass = string.unpack('>I2', buf:sub(pos + 2))
    if qclass ~= 1 then
        return nil, string.format('unknown query class %d in DNS response', qclass)
    end

    pos = pos + 4

    local answers = {}

    if code ~= 0 then
        return nil, resolver_errstrs[code] or 'unknown'
    end

    local err

    pos, err = parse_section(answers, M.SECTION_AN, buf, pos, nan)

    if not pos then
        return nil, err
    end

    return answers
end

local function query(s, id, req, nameserver)
    local host, port = nameserver[1], nameserver[2]
    local n, err = s:sendto(req, host, port)
    if not n then
        return nil, string.format('sendto "%s:%d" fail: %s', host, port, err)
    end

    local data, err = s:recvfrom(512, 3.0)
    if not data then
        return nil, string.format('recv from "%s:%d" fail: %s', host, port, err)
    end

    return parse_response(data, id)
end

--[[
    opts is an optional Table that supports the following fields:
    type: The current resource record type, possible values are 1 (TYPE_A), 5 (TYPE_CNAME),
            28 (TYPE_AAAA), and any other values allowed by RFC 1035.
    no_recurse: a boolean flag controls whether to disable the "recursion desired" (RD) flag
                in the UDP request. Defaults to false
    nameservers: a list of nameservers to be used. Each nameserver entry can be either a
                single hostname string or a table holding both the hostname string and the port number.
--]]
function M.query(qname, opts)
    if string.byte(qname, 1) == string.byte('.') or #qname > 255 then
        return nil, 'bad name'
    end

    if socket.is_ipv4_address(qname) then
        return { {
            type = M.TYPE_A,
            address = qname
        } }
    end

    if socket.is_ipv6_address(qname) then
        return { {
            type = M.TYPE_AAAA,
            address = qname
        } }
    end

    opts = opts or {}

    local nameservers = {}

    for _, nameserver in ipairs(opts.nameservers or {}) do
        local host, port

        if type(nameserver) == 'string' then
            host = nameserver
            port = 53
        elseif type(nameserver) == 'table' then
            host = nameserver[1]
            port = nameserver[2] or 53
        else
            error('invalid nameservers')
        end

        if not socket.is_ip_address(host) then
            error('invalid nameserver: ' .. nameserver)
        end

        nameservers[#nameservers + 1] = { host, port, socket.is_ipv6_address(host) }
    end

    local resolvconf = parse_resolvconf()

    for _, nameserver in ipairs(resolvconf.nameservers) do
        nameservers[#nameservers + 1] = nameserver
    end

    if #nameservers < 1 then
        error('not found valid nameservers')
    end

    if not qname:match('%.') and resolvconf.search then
        qname = qname .. '.' .. resolvconf.search
    end

    local err

    for _, nameserver in ipairs(nameservers) do
        local id = get_next_transaction_id()

        local req
        req, err = build_request(qname, id, opts)
        if not req then
            return nil, err
        end

        local s

        if nameserver[3] then
            s, err = socket.udp6()
        else
            s, err = socket.udp()
        end
        if not s then
            return err
        end

        local answers
        answers, err = query(s, id, req, nameserver)
        s:close()

        if answers then
            return answers
        end
    end

    return nil, err
end

function M.type_name(n)
    local names = {
        [M.TYPE_A]      = 'A',
        [M.TYPE_NS]     = 'NS',
        [M.TYPE_CNAME]  = 'CNAME',
        [M.TYPE_SOA]    = 'SOA',
        [M.TYPE_PTR]    = 'PTR',
        [M.TYPE_MX]     = 'MX',
        [M.TYPE_TXT]    = 'TXT',
        [M.TYPE_AAAA]   = 'AAAA',
        [M.TYPE_SRV]    = 'SRV',
        [M.TYPE_SPF]    = 'SPF'
    }

    return names[n] or 'unknown'
end

return M
