-- SPDX-License-Identifier: MIT
-- Author: Jianhui Zhao <zhaojh329@gmail.com>

--- Command-line argument parsing utilities.
--
-- @module eco.cli

local M = {}

local TYPES = {
    boolean = true,
    string = true,
    number = true,
    integer = true,
    count = true,
    array = true
}

local VALUE_TYPES = {
    string = true,
    number = true,
    integer = true,
    array = true
}

local function fail(fmt, ...)
    return nil, string.format(fmt, ...)
end

local function validate_array_default(name, default)
    if default == nil then
        return true
    end

    if type(default) ~= 'table' then
        return fail("option '%s' default must be an array table", name)
    end

    local n = #default
    local count = 0

    for key, value in pairs(default) do
        if type(key) ~= 'number' or math.type(key) ~= 'integer' or key < 1 then
            return fail("option '%s' default must be an array table", name)
        end

        if type(value) ~= 'string' then
            return fail("option '%s' default array item #%d must be a string", name, key)
        end

        count = count + 1
    end

    if count ~= n then
        return fail("option '%s' default array must not contain holes", name)
    end

    return true
end

local function set_default(opts, opt)
    local name = opt.name

    if opt.default ~= nil then
        if opt.type == 'array' and type(opt.default) == 'table' then
            local default = {}
            for i = 1, #opt.default do
                default[i] = opt.default[i]
            end
            opts[name] = default
        else
            opts[name] = opt.default
        end
        return
    end

    if opt.type == 'boolean' then
        opts[name] = false
    elseif opt.type == 'count' then
        opts[name] = 0
    end
end

local function normalize_specs(spec)
    if type(spec) ~= 'table' then
        return fail('spec must be a table')
    end

    local specs = {}
    local by_short = {}
    local by_long = {}
    local by_name = {}

    for i = 1, #spec do
        local opt = spec[i]

        if type(opt) ~= 'table' then
            return fail('invalid option spec #%d', i)
        end

        local name = opt.name
        if type(name) ~= 'string' or name == '' then
            return fail("option spec #%d requires a non-empty 'name'", i)
        end

        local typ = opt.type
        if typ == nil then
            typ = 'boolean'
        elseif type(typ) ~= 'string' then
            return fail("option '%s' type must be a string or nil", name)
        end

        if not TYPES[typ] then
            return fail("option '%s' has unsupported type '%s'", name, tostring(typ))
        end

        if typ == 'array' then
            local ok, err = validate_array_default(name, opt.default)
            if not ok then
                return nil, err
            end
        end

        if by_name[name] then
            return fail("option name '%s' specified multiple times", name)
        end
        by_name[name] = true

        local long = opt.long
        if long == nil then
            long = name
        elseif type(long) ~= 'string' or long == '' then
            return fail("option '%s' has invalid long name", name)
        end

        if by_long[long] then
            return fail("long option '%s' specified multiple times", long)
        end

        local short = opt.short
        if short ~= nil then
            if type(short) ~= 'string' or #short ~= 1 then
                return fail("option '%s' short name must be one character", name)
            end

            if by_short[short] then
                return fail("short option '-%s' specified multiple times", short)
            end
        end

        local normalized = {
            name = name,
            short = short,
            long = long,
            type = typ,
            default = opt.default,
            required = opt.required and true or false
        }

        specs[#specs + 1] = normalized
        by_long[long] = normalized

        if short then
            by_short[short] = normalized
        end
    end

    return specs, by_short, by_long
end

local function convert_value(opt, value, has_value)
    local typ = opt.type

    if typ == 'boolean' or typ == 'count' then
        if has_value then
            return fail("option '%s' does not take a value", opt.name)
        end

        return true
    end

    if not has_value then
        return fail("option '%s' requires a value", opt.name)
    end

    if typ == 'string' or typ == 'array' then
        return value
    end

    local n = tonumber(value)
    if not n then
        if typ == 'integer' then
            return fail("option '%s' expects an integer", opt.name)
        end

        return fail("option '%s' expects a %s", opt.name, typ)
    end

    if typ == 'integer' then
        n = math.tointeger(n)
        if not n then
            return fail("option '%s' expects an integer", opt.name)
        end
    end

    return n
end

local function apply_option(opts, seen, opt, value, has_value)
    local converted, err = convert_value(opt, value, has_value)

    if converted == nil then
        return nil, err
    end

    local name = opt.name
    local typ = opt.type

    if typ ~= 'array' and typ ~= 'count' and seen[name] then
        return fail("option '%s' specified multiple times", name)
    end

    seen[name] = true

    if typ == 'array' then
        local values = opts[name]

        if values == nil then
            values = {}
            opts[name] = values
        elseif type(values) ~= 'table' then
            return fail("option '%s' default must be an array table", name)
        end

        values[#values + 1] = converted
        return true
    end

    if typ == 'count' then
        opts[name] = (opts[name] or 0) + 1
        return true
    end

    opts[name] = converted

    return true
end

--- Parse command-line options and positional arguments.
--
-- The parser follows POSIX/GNU `getopt_long`-style conventions: long
-- options use `--name` or `--name=value`, short options use `-x`, and
-- single-dash multi-character forms are parsed as short option bundles or
-- short option values, not as long options. Use `--` to stop option parsing.
--
-- Parsed option values are returned in a result table keyed by option
-- `name`; positional arguments are returned in `result.args`. If `argv` is
-- omitted, the global `arg` table is used and `arg[0]` is ignored.
--
-- Each option supports these fields:
--
-- - `name` (required): result field name and default long option name
-- - `short`: one-character short option
-- - `long`: long option name; defaults to `name`
-- - `type`: `"boolean"` (default), `"string"`, `"number"`, `"integer"`,
--   `"count"` or `"array"`
-- - `default`: default value; array defaults must be arrays of strings
-- - `required`: fail if the option is not present
--
-- Supported value forms include `--name value`, `--name=value`, `-x value`,
-- and `-xvalue`. Boolean and count short options may be bundled, such as
-- `-vvq`.
--
-- @function parse_args
-- @tparam table spec Option specification array.
-- @tparam[opt] table argv Argument array. Defaults to global `arg`.
-- @treturn table Parsed options with positional arguments in `args`.
-- @treturn[2] nil On parse failure.
-- @treturn[2] string Error message.
-- @usage
-- local cli = require 'eco.cli'
-- local opts, err = cli.parse_args({
--     { name = 'dev', short = 'i', type = 'string', required = true },
--     { name = 'promisc', short = 'p' },
--     { name = 'verbose', short = 'v', type = 'count', default = 0 },
--     { name = 'include', short = 'I', type = 'array' },
-- })
-- if not opts then
--     io.stderr:write(err, '\n')
--     os.exit(1)
-- end
function M.parse_args(spec, argv)
    local specs, by_short, by_long = normalize_specs(spec)

    if not specs then
        return nil, by_short
    end

    if argv == nil then
        argv = _G.arg or {}
    elseif type(argv) ~= 'table' then
        return nil, 'argv must be a table'
    end

    local opts = { args = {} }
    local args = opts.args
    local seen = {}
    local parse_options = true

    for i = 1, #specs do
        set_default(opts, specs[i])
    end

    local i = 1
    while i <= #argv do
        local arg = argv[i]

        if type(arg) ~= 'string' then
            return fail('argument #%d must be a string', i)
        end

        if not parse_options or #arg < 2 or arg:sub(1, 1) ~= '-' or arg == '-' then
            args[#args + 1] = arg
        elseif arg == '--' then
            parse_options = false
        elseif arg:sub(1, 2) == '--' then
            local body = arg:sub(3)
            local key, value = body:match('^([^=]*)=(.*)$')
            local has_value = key ~= nil

            if not key then
                key = body
            end

            if key == '' then
                return fail("unknown option '%s'", arg)
            end

            local opt = by_long[key]
            if not opt then
                return fail("unknown option '%s'", arg)
            end

            if VALUE_TYPES[opt.type] and not has_value then
                if i >= #argv then
                    return fail("option '%s' requires a value", opt.name)
                end

                i = i + 1
                value = argv[i]
                if type(value) ~= 'string' then
                    return fail('argument #%d must be a string', i)
                end
                has_value = true
            end

            local ok, err = apply_option(opts, seen, opt, value, has_value)
            if not ok then
                return nil, err
            end
        else
            local pos = 2

            while pos <= #arg do
                local short = arg:sub(pos, pos)
                local opt = by_short[short]

                if not opt then
                    return fail("unknown option '-%s'", short)
                end

                local value
                local has_value = false

                if VALUE_TYPES[opt.type] then
                    if pos < #arg then
                        value = arg:sub(pos + 1)
                        has_value = true
                        pos = #arg
                    else
                        if i >= #argv then
                            return fail("option '%s' requires a value", opt.name)
                        end

                        i = i + 1
                        value = argv[i]
                        if type(value) ~= 'string' then
                            return fail('argument #%d must be a string', i)
                        end
                        has_value = true
                    end
                end

                local ok, err = apply_option(opts, seen, opt, value, has_value)
                if not ok then
                    return nil, err
                end

                pos = pos + 1
            end
        end

        i = i + 1
    end

    for n = 1, #specs do
        local opt = specs[n]

        if opt.required and not seen[opt.name] then
            return fail("required option '%s' is missing", opt.name)
        end
    end

    return opts
end

return M
