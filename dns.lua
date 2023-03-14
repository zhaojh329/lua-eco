-- SPDX-License-Identifier: MIT
-- Author: Jianhui Zhao <zhaojh329@gmail.com>

-- Referenced from https://github.com/openresty/lua-resty-dns/blob/master/lib/resty/dns/resolver.lua

local socket = require 'eco.socket'
local bit = require 'eco.bit'

local char = string.char

local rshift = bit.rshift
local lshift = bit.lshift
local band = bit.band

local TYPE_A      = 1
local TYPE_NS     = 2
local TYPE_CNAME  = 5
local TYPE_SOA    = 6
local TYPE_PTR    = 12
local TYPE_MX     = 15
local TYPE_TXT    = 16
local TYPE_AAAA   = 28
local TYPE_SRV    = 33
local TYPE_SPF    = 99

local CLASS_IN    = 1

local SECTION_AN  = 1
local SECTION_NS  = 2
local SECTION_AR  = 3

local M = {
    TYPE_A      = TYPE_A,
    TYPE_NS     = TYPE_NS,
    TYPE_CNAME  = TYPE_CNAME,
    TYPE_SOA    = TYPE_SOA,
    TYPE_PTR    = TYPE_PTR,
    TYPE_MX     = TYPE_MX,
    TYPE_TXT    = TYPE_TXT,
    TYPE_AAAA   = TYPE_AAAA,
    TYPE_SRV    = TYPE_SRV,
    TYPE_SPF    = TYPE_SPF,
    CLASS_IN    = CLASS_IN,
    SECTION_AN  = SECTION_AN,
    SECTION_NS  = SECTION_NS,
    SECTION_AR  = SECTION_AR
}

local resolver_errstrs = {
    'format error',     -- 1
    'server failure',   -- 2
    'name error',       -- 3
    'not implemented',  -- 4
    'refused',          -- 5
}

local soa_int32_fields = { 'serial', 'refresh', 'retry', 'expire', 'minimum' }

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

local function gen_id()
    return math.random(0, 65535)
end

local function build_request(qname, id, opts)
    local ident_hi = char(rshift(id, 8))
    local ident_lo = char(band(id, 0xff))

    opts = opts or {}

    local qtype = opts.type or TYPE_A

    local flags
    if opts.no_recurse then
        flags = "\0\0"
    else
        flags = "\1\0"
    end

    local nqs = '\0\1'
    local nan = '\0\0'
    local nns = '\0\0'
    local nar = '\0\0'
    local typ = char(rshift(qtype, 8), band(qtype, 0xff))
    local class = '\0\1'

    if string.byte(qname, 1) == string.byte('.') then
        return nil, 'bad name'
    end

    local name = qname:gsub('([^.]+)%.?', function(s)
        return char(#s) .. s
    end) .. '\0'

    return table.concat({
        ident_hi, ident_lo, flags, nqs, nan, nns, nar,
        name, typ, class
    })
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

        if band(fst, 0xc0) ~= 0 then
            -- being a pointer
            if nptrs == 0 then
                pos = pos + 2
            end

            nptrs = nptrs + 1

            local snd = string.byte(buf, p + 1)
            if not snd then
                return nil, 'truncated'
            end

            p = lshift(band(fst, 0x3f), 8) + snd + 1
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

local function parse_section(answers, section, buf, start_pos, size, should_skip)
    local pos = start_pos

    for _ = 1, size do
        local ans = {}

        if not should_skip then
            answers[#answers + 1] = ans
        end

        ans.section = section

        local name
        name, pos = decode_name(buf, pos)
        if not name then
            return nil, pos
        end

        ans.name = name

        local type_hi = string.byte(buf, pos)
        local type_lo = string.byte(buf, pos + 1)
        local typ = lshift(type_hi, 8) + type_lo

        ans.type = typ

        local class_hi = string.byte(buf, pos + 2)
        local class_lo = string.byte(buf, pos + 3)
        local class = lshift(class_hi, 8) + class_lo

        ans.class = class

        local byte_1, byte_2, byte_3, byte_4 = string.byte(buf, pos + 4, pos + 7)

        local ttl = lshift(byte_1, 24) + lshift(byte_2, 16) + lshift(byte_3, 8) + byte_4

        ans.ttl = ttl

        local len_hi = string.byte(buf, pos + 8)
        local len_lo = string.byte(buf, pos + 9)
        local len = lshift(len_hi, 8) + len_lo

        pos = pos + 10

        if typ == TYPE_A then

            if len ~= 4 then
                return nil, 'bad A record value length: ' .. len
            end

            local addr_bytes = { string.byte(buf, pos, pos + 3) }
            local addr = table.concat(addr_bytes, '.')

            ans.address = addr

            pos = pos + 4

        elseif typ == TYPE_CNAME then

            local cname, p = decode_name(buf, pos)
            if not cname then
                return nil, pos
            end

            if p - pos ~= len then
                return nil, string.format('bad cname record length: %d ~= %d', p - pos, len)
            end

            pos = p

            ans.cname = cname

        elseif typ == TYPE_AAAA then

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

        elseif typ == TYPE_MX then

            if len < 3 then
                return nil, 'bad MX record value length: ' .. len
            end

            local pref_hi = string.byte(buf, pos)
            local pref_lo = string.byte(buf, pos + 1)

            ans.preference = lshift(pref_hi, 8) + pref_lo

            local host, p = decode_name(buf, pos + 2)
            if not host then
                return nil, pos
            end

            if p - pos ~= len then
                return nil, string.format('bad cname record length: %d ~= %d', p - pos, len)
            end

            ans.exchange = host

            pos = p

        elseif typ == TYPE_SRV then
            if len < 7 then
                return nil, 'bad SRV record value length: ' .. len
            end

            local prio_hi = string.byte(buf, pos)
            local prio_lo = string.byte(buf, pos + 1)
            ans.priority = lshift(prio_hi, 8) + prio_lo

            local weight_hi = string.byte(buf, pos + 2)
            local weight_lo = string.byte(buf, pos + 3)
            ans.weight = lshift(weight_hi, 8) + weight_lo

            local port_hi = string.byte(buf, pos + 4)
            local port_lo = string.byte(buf, pos + 5)
            ans.port = lshift(port_hi, 8) + port_lo

            local name, p = decode_name(buf, pos + 6)
            if not name then
                return nil, pos
            end

            if p - pos ~= len then
                return nil, string.format('bad srv record length: %d ~= %d', p - pos, len)
            end

            ans.target = name

            pos = p

        elseif typ == TYPE_NS then

            local name, p = decode_name(buf, pos)
            if not name then
                return nil, pos
            end

            if p - pos ~= len then
                return nil, string.format('bad cname record length: %d ~= %d', p - pos, len)
            end

            pos = p

            ans.nsdname = name

        elseif typ == TYPE_TXT or typ == TYPE_SPF then

            local key = (typ == TYPE_TXT) and 'txt' or 'spf'

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
                    local slen = string.byte(buf, pos)
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

        elseif typ == TYPE_PTR then

            local name, p = decode_name(buf, pos)
            if not name then
                return nil, pos
            end

            if p - pos ~= len then
                return nil, string.format('bad cname record length: %d ~= %d', p - pos, len)
            end

            pos = p

            ans.ptrdname = name

        elseif typ == TYPE_SOA then
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
                local byte_1, byte_2, byte_3, byte_4 = string.byte(buf, p, p + 3)
                ans[field] = lshift(byte_1, 24) + lshift(byte_2, 16) + lshift(byte_3, 8) + byte_4
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
    local ident_hi = string.byte(buf, 1)
    local ident_lo = string.byte(buf, 2)
    local ans_id = lshift(ident_hi, 8) + ident_lo

    if ans_id ~= id then
        return nil, 'id mismatch'
    end

    local flags_hi = string.byte(buf, 3)
    local flags_lo = string.byte(buf, 4)
    local flags = lshift(flags_hi, 8) + flags_lo

    if band(flags, 0x8000) == 0 then
        return nil, 'bad QR flag in the DNS response'
    end

    if band(flags, 0x200) ~= 0 then
        return nil, 'truncated'
    end

    local code = band(flags, 0xf)

    local nqs_hi = string.byte(buf, 5)
    local nqs_lo = string.byte(buf, 6)
    local nqs = lshift(nqs_hi, 8) + nqs_lo

    if nqs ~= 1 then
        return nil, string.format('bad number of questions in DNS response: %d', nqs)
    end

    local nan_hi = string.byte(buf, 7)
    local nan_lo = string.byte(buf, 8)
    local nan = lshift(nan_hi, 8) + nan_lo

    -- skip the question part
    local ans_qname, pos = decode_name(buf, 13)
    if not ans_qname then
        return nil, pos
    end

    if pos + 3 + nan * 12 > n then
        return nil, 'truncated';
    end

    local class_hi = string.byte(buf, pos + 2)
    local class_lo = string.byte(buf, pos + 3)
    local qclass = lshift(class_hi, 8) + class_lo

    if qclass ~= 1 then
        return nil, string.format('unknown query class %d in DNS response', qclass)
    end

    pos = pos + 4

    local answers = {}

    if code ~= 0 then
        answers.errcode = code
        answers.errstr = resolver_errstrs[code] or 'unknown'
    end

    local err

    pos, err = parse_section(answers, SECTION_AN, buf, pos, nan)

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
    if socket.is_ipv4_address(qname) then
        return { {
            type = TYPE_A,
            address = qname
        } }
    end

    if socket.is_ipv6_address(qname) then
        return { {
            type = TYPE_AAAA,
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
        local id = gen_id()

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

return M
