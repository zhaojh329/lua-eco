local socket = require 'eco.socket'
local bufio = require 'eco.bufio'
local file = require 'eco.file'
local eco = require 'eco'

local M = {}

local srv_methods = {}

function srv_methods:close()
    if self.closed then
        return
    end

    self.closed = true
    self.sock:close()
end

local srv_mt = {
    __index = srv_methods,
    __gc = srv_methods.close,
    __close = srv_methods.close
}

local function handle_conn(self, c)
    local con<close> = c
    local b = bufio.new(con)

    local action = b:read('l', 3.0)
    if not action then
        return
    end

    if action ~= 'get' and action ~= 'set' and action ~= 'del' then
        return
    end

    local key = b:read('l', 3.0)
    if not key then
        return
    end

    if action == 'get' then
        local value = self.dict[key]
        if value then
            c:write(value .. '\n')
        end
    elseif action == 'set' then
        local value = b:read('l', 3.0)
        if not value then
            return
        end

        self.dict[key] = value
    elseif action == 'del' then
        self.dict[key] = nil
    end
end

local function handle_accept(self)
    while not self.closed do
        local conn, err = self.sock:accept()
        if not conn then
            return nil, err
        end

        eco.run(handle_conn, self, conn)
    end
end

function M.new(name)
    assert(name, 'name is required')

    local path = '/var/run/eco-shared-' .. name .. '.sock'

    if file.access(path) then
        return nil, 'name already exists'
    end

    local sock, err = socket.listen_unix(path)
    if not sock then
        return nil, err
    end

    local self = {
        sock = sock,
        dict = {}
    }

    eco.run(handle_accept, self)

    return setmetatable(self, srv_mt)
end

local cli_methods = {}

local function cli_connect(self)
    local sock, err = socket.connect_unix(self.path)
    if not sock then
        return nil, err
    end

    return sock
end

function cli_methods:get(name)
    local sock<close>, err = cli_connect(self)
    if not sock then
        return nil, err
    end

    sock:write('get\n')
    sock:write(name .. '\n')

    local b = bufio.new(sock)
    local value = b:read('l')
    return value
end

function cli_methods:set(name, value)
    local typ = type(value)
    assert(typ == 'number' or typ == 'string', 'value must be number or string')

    local sock<close>, err = cli_connect(self)
    if not sock then
        return nil, err
    end

    sock:write('set\n')
    sock:write(name .. '\n')
    sock:write(value .. '\n')
end

function cli_methods:del(name)
    local sock<close>, err = cli_connect(self)
    if not sock then
        return nil, err
    end

    sock:write('del\n')
    sock:write(name .. '\n')
end

function cli_methods:close()
    if self.closed then
        return
    end

    self.closed = true
    self.sock:close()
end

local cli_mt = {
    __index = cli_methods,
    __gc = cli_methods.close,
    __close = cli_methods.close
}

function M.get(name)
    assert(name, 'name is required')

    local self = {
        path = '/var/run/eco-shared-' .. name .. '.sock'
    }

    return setmetatable(self, cli_mt)
end

return M
