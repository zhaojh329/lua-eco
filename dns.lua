-- SPDX-License-Identifier: MIT
-- Author: Jianhui Zhao <zhaojh329@gmail.com>
--
--- DNS resolver utilities.
--
-- This module implements a simple DNS client over UDP.
--
-- It resolves names using:
--
-- - `/etc/hosts` first
-- - then DNS servers from `opts.nameservers` or `/etc/resolv.conf`
--
-- @module eco.dns

local file = require 'eco.internal.file'
local dns = require 'eco.internal.dns'
local socket = require 'eco.socket'
local time = require 'eco.time'

local M = {
    --- Resource record type: A.
    TYPE_A      = 1,
    --- Resource record type: NS.
    TYPE_NS     = 2,
    --- Resource record type: CNAME.
    TYPE_CNAME  = 5,
    --- Resource record type: SOA.
    TYPE_SOA    = 6,
    --- Resource record type: PTR.
    TYPE_PTR    = 12,
    --- Resource record type: MX.
    TYPE_MX     = 15,
    --- Resource record type: TXT.
    TYPE_TXT    = 16,
    --- Resource record type: AAAA.
    TYPE_AAAA   = 28,
    --- Resource record type: SRV.
    TYPE_SRV    = 33,
    --- Resource record type: SPF.
    TYPE_SPF    = 99,

    --- DNS class: IN (Internet).
    CLASS_IN    = 1,

    --- DNS answer section: Answer.
    SECTION_AN  = 1,
    --- DNS answer section: Authority.
    SECTION_NS  = 2,
    --- DNS answer section: Additional.
    SECTION_AR  = 3
}

local RESOLV_CONF_PATH = '/etc/resolv.conf'
local HOSTS_PATH = '/etc/hosts'

local resolv_cache = {
    version = nil,
    conf = nil
}

local hosts_cache = {
    version = nil,
    index = nil
}

local function get_file_version(path)
    if not file.access(path, 'r') then
        return nil
    end

    local st = file.stat(path)
    if not st then
        return nil
    end

    return st.mtime
end

local function build_hosts_index()
    local index = {
        [M.TYPE_A] = {},
        [M.TYPE_AAAA] = {}
    }

    for line in io.lines(HOSTS_PATH) do
        if line:sub(1, 1) ~= '#' and line ~= '' then
            local fields = {}

            for field in line:gmatch('%S+') do
                fields[#fields + 1] = field
            end

            local address = fields[1]
            local address_type

            if socket.is_ipv4_address(address) then
                address_type = M.TYPE_A
            elseif socket.is_ipv6_address(address) then
                address_type = M.TYPE_AAAA
            end

            if address_type and #fields > 1 then
                local names = index[address_type]

                for i = 2, #fields do
                    local name = fields[i]
                    if name:sub(1, 1) == '#' then
                        break
                    end

                    if not names[name] then
                        names[name] = address
                    end
                end
            end
        end
    end

    return index
end

local function parse_resolvconf()
    local version = get_file_version(RESOLV_CONF_PATH)
    if not version then
        return
    end

    if version == resolv_cache.version then
        return resolv_cache.conf
    end

    local nameservers = {}
    local conf = {}

    for line in io.lines(RESOLV_CONF_PATH) do
        line = line:gsub('[#;].*', '')
        local directive, value = line:match('^%s*(%S+)%s+(%S+)')

        if directive == 'search' then
            -- Only the first search suffix is used by this resolver.
            conf.search = value
        elseif directive == 'nameserver' and socket.is_ip_address(value) then
            nameservers[#nameservers + 1] = { value, 53, socket.is_ipv6_address(value) }
        end
    end

    if #nameservers == 0 then
        nameservers[#nameservers + 1] = { '127.0.0.1', 53 }
    end

    conf.nameservers = nameservers

    resolv_cache.version = version
    resolv_cache.conf = conf

    return conf
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
        id, flags, nqs, nan, nns, nar, name, opts.type, M.CLASS_IN)
end

local function query(s, req, nameserver)
    local host, port = nameserver[1], nameserver[2]

    local ok, err = s:connect(host, port)
    if not ok then
        return nil, string.format('connect "%s:%d" fail: %s', host, port, err)
    end

    local n, err = s:send(req)
    if not n then
        return nil, string.format('send "%s:%d" fail: %s', host, port, err)
    end

    local deadline = time.now(time.CLOCK_MONOTONIC) + 5.0

    while true do
        local remaining = deadline - time.now(time.CLOCK_MONOTONIC)
        if remaining <= 0 then
            return nil, string.format('recv from "%s:%d" fail: timeout', host, port)
        end

        local data, err = s:recvfrom(512, remaining)
        if not data then
            return nil, string.format('recv from "%s:%d" fail: %s', host, port, err)
        end

        local answers, err = dns.parse_response(data, req)
        if answers or err then
            return answers, err
        end
    end
end

local function name_from_hosts(qname, opts)
    local typ = opts.type
    if typ ~= M.TYPE_A and typ ~= M.TYPE_AAAA then
        return
    end

    local version = get_file_version(HOSTS_PATH)
    if not version then
        return
    end

    if hosts_cache.version ~= version then
        hosts_cache.version = version
        hosts_cache.index = build_hosts_index()
    end

    local address = hosts_cache.index[typ][qname]

    if address then
        return {{
            type = typ,
            address = address
        }}
    end
end

--- Resolve a DNS name.
--
-- The return value is an array of answer records. Record table fields depend
-- on the record type. Common fields:
--
-- - `name`, `type`, `class`, `ttl`, `section`
--
-- Type-specific fields include:
--
-- - `A/AAAA`: `address`
-- - `CNAME`: `cname`
-- - `MX`: `preference`, `exchange`
-- - `SRV`: `priority`, `weight`, `port`, `target`
-- - `NS`: `nsdname`
-- - `TXT`: `txt` (string or array of strings)
-- - `SPF`: `spf` (string or array of strings)
-- - `PTR`: `ptrdname`
-- - `SOA`: `mname`, `rname`, `serial`, `refresh`, `retry`, `expire`, `minimum`
--
-- @function query
-- @tparam string qname Domain name or IP address.
-- @tparam[opt] table opts Options:
--
-- - `type` (int) RR type (default @{TYPE_A}).
-- - `no_recurse` (boolean) Disable recursion desired (RD) flag.
-- - `nameservers` (table) Nameserver list. Each entry can be:
--   - `"ip"` string
--   - `{ ip, port }` table
-- - `mark` (number) SO_MARK for the UDP socket.
-- - `device` (string) SO_BINDTODEVICE for the UDP socket.
--
-- @treturn table answers
-- @treturn[2] nil On failure.
-- @treturn[2] string Error message.
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
    opts.type = opts.type or M.TYPE_A

    local res = name_from_hosts(qname, opts)
    if res then
        return res
    end

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

    local resolvconf = parse_resolvconf() or { nameservers = {{ '127.0.0.1', 53 }} }

    if #nameservers == 0 then
        for _, nameserver in ipairs(resolvconf.nameservers) do
            nameservers[#nameservers + 1] = nameserver
        end
    end

    if #nameservers < 1 then
        return nil, 'not found valid nameservers'
    end

    if not qname:match('%.') and resolvconf.search then
        qname = qname .. '.' .. resolvconf.search
    end

    local id, ok, answers, err

    for _, nameserver in ipairs(nameservers) do
        id, err = dns.transaction_id()
        if not id then
            return nil, err
        end

        local req = build_request(qname, id, opts)

        local s<close>, socket_err = (nameserver[3] and socket.udp6 or socket.udp)()
        if not s then
            return nil, socket_err
        end

        if opts.mark then
            ok, err = s:setoption('mark', opts.mark)
            if not ok then
                return nil, err
            end
        end

        if opts.device then
            ok, err = s:setoption('bindtodevice', opts.device)
            if not ok then
                return nil, err
            end
        end

        answers, err = query(s, req, nameserver)
        if answers then
            return answers
        end
    end

    return nil, err
end

--- Convert RR type number to its mnemonic.
--
-- @function type_name
-- @tparam integer n RR type number.
-- @treturn string
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
