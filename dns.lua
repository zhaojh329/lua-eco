-- SPDX-License-Identifier: MIT
-- Author: Jianhui Zhao <zhaojh329@gmail.com>

-- Referenced from https://github.com/openresty/lua-resty-dns/blob/master/lib/resty/dns/resolver.lua

local file = require 'eco.core.file'
local socket = require 'eco.socket'
local dns = require 'eco.core.dns'

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

local transaction_id_init

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
        if line:match('search') then
            local search = line:match('search%s+(%S+)')
            if not search:match('%.') then
                conf.search = search
            end
        elseif line:match('nameserver') then
            local nameserver = line:match('nameserver%s+(%S+)')
            if nameserver then
                if socket.is_ipv4_address(nameserver) or socket.is_ipv6_address(nameserver) then
                    nameservers[#nameservers + 1] = { nameserver, 53, socket.is_ipv6_address(nameserver) }
                end
            end
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

local function query(s, id, req, nameserver)
    local host, port = nameserver[1], nameserver[2]
    local n, err = s:sendto(req, host, port)
    if not n then
        return nil, string.format('sendto "%s:%d" fail: %s', host, port, err)
    end

    local data, err = s:recv(512, 5.0)
    if not data then
        return nil, string.format('recv from "%s:%d" fail: %s', host, port, err)
    end

    return dns.parse_response(data, id)
end

local function name_from_hosts(qname, opts)
    local version = get_file_version(HOSTS_PATH)
    if not version then
        return
    end

    if hosts_cache.version ~= version then
        hosts_cache.version = version
        hosts_cache.index = build_hosts_index()
    end

    local typ = opts.type or M.TYPE_A
    local address = hosts_cache.index[typ][qname]

    if address then
        return {{
            type = typ,
            address = address
        }}
    end
end

--[[
    opts is an optional Table that supports the following fields:
    type: The current resource record type, possible values are 1 (TYPE_A), 5 (TYPE_CNAME),
            28 (TYPE_AAAA), and any other values allowed by RFC 1035.
    no_recurse: a boolean flag controls whether to disable the "recursion desired" (RD) flag
                in the UDP request. Defaults to false
    nameservers: a list of nameservers to be used. Each nameserver entry can be either a
                single hostname string or a table holding both the hostname string and the port number.
    mark: a number used to set SO_MARK to socket
    device: a string used to set SO_BINDTODEVICE to socket
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

    local answers, err

    for _, nameserver in ipairs(nameservers) do
        local id = get_next_transaction_id()

        local req = build_request(qname, id, opts)

        local s<close> = nameserver[3] and socket.udp6() or socket.udp()

        if opts.mark then
            s:setoption('mark', opts.mark)
        end

        if opts.device then
            s:setoption('bindtodevice', opts.device)
        end

        answers, err = query(s, id, req, nameserver)
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
