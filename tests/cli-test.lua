#!/usr/bin/env eco

local cli = require 'eco.cli'

local function run_case(name, fn)
    local ok, err = pcall(fn)
    assert(ok, name .. ': ' .. tostring(err))
end

local function expect_parse_error(spec, argv, needle)
    local opts, err = cli.parse_args(spec, argv)

    assert(opts == nil, 'parse_args should fail')
    assert(type(err) == 'string' and err:find(needle, 1, true),
           string.format('expected parse error containing %q, got %q', needle, tostring(err)))
end

run_case('parse common option forms', function()
    local spec = {
        { name = 'name', short = 'n', type = 'string', required = true },
        { name = 'dry_run', long = 'dry-run' },
        { name = 'quiet', short = 'q' },
        { name = 'verbose', short = 'v', type = 'count', default = 0 },
        { name = 'include', short = 'I', type = 'array' },
        { name = 'port', type = 'integer', default = 80 },
        { name = 'ratio', type = 'number' },
        { name = 'level', type = 'integer', default = 3 },
    }

    local opts, err = cli.parse_args(spec, {
        '-vv',
        '-I', 'src',
        '--include=lib',
        '--dry-run',
        '--name', 'demo',
        '--port=8080.0',
        '--ratio', '1.5',
        'pos1',
        '--',
        '--literal',
        '-x',
    })

    assert(opts, err)
    assert(opts.name == 'demo')
    assert(opts.dry_run == true)
    assert(opts.quiet == false)
    assert(opts.verbose == 2)
    assert(opts.include[1] == 'src' and opts.include[2] == 'lib' and #opts.include == 2)
    assert(opts.port == 8080)
    assert(math.type(opts.port) == 'integer')
    assert(opts.ratio == 1.5)
    assert(opts.level == 3)
    assert(opts.args[1] == 'pos1')
    assert(opts.args[2] == '--literal')
    assert(opts.args[3] == '-x')
    assert(#opts.args == 3)
end)

run_case('parse bundled short options', function()
    local opts, err = cli.parse_args({
        { name = 'alpha', short = 'a' },
        { name = 'beta', short = 'b' },
        { name = 'count', short = 'c', type = 'count' },
        { name = 'output', short = 'o', type = 'string' },
    }, { '-abc', '-ofile' })

    assert(opts, err)
    assert(opts.alpha == true)
    assert(opts.beta == true)
    assert(opts.count == 1)
    assert(opts.output == 'file')
end)

run_case('copy array defaults before appending', function()
    local default_include = { 'base' }
    local opts, err = cli.parse_args({
        { name = 'include', short = 'I', type = 'array', default = default_include },
    }, { '-Iextra' })

    assert(opts, err)
    assert(opts.include[1] == 'base')
    assert(opts.include[2] == 'extra')
    assert(#default_include == 1 and default_include[1] == 'base')
end)

run_case('parse global arg by default', function()
    local old_arg = arg
    arg = { [0] = 'prog', '--name=bob', 'file' }

    local opts, err = cli.parse_args({
        { name = 'name', type = 'string', required = true },
    })

    arg = old_arg

    assert(opts, err)
    assert(opts.name == 'bob')
    assert(opts.args[1] == 'file' and #opts.args == 1)
end)

run_case('missing global arg is empty argv', function()
    local old_arg = arg
    arg = nil

    local opts, err = cli.parse_args({})

    arg = old_arg

    assert(opts, err)
    assert(#opts.args == 0)
end)

run_case('parse errors', function()
    local spec = {
        { name = 'name', short = 'n', type = 'string', required = true },
        { name = 'port', type = 'integer' },
        { name = 'ratio', type = 'number' },
        { name = 'flag' },
    }

    expect_parse_error(spec, { '--unknown' }, 'unknown option')
    expect_parse_error(spec, { '--name' }, 'requires a value')
    expect_parse_error(spec, { '--name', 'a', '--port', 'x' }, 'expects an integer')
    expect_parse_error(spec, { '--name', 'a', '--ratio=' }, 'expects a number')
    expect_parse_error(spec, { '--name', 'a', '--name', 'b' }, 'specified multiple times')
    expect_parse_error(spec, { '--flag=true' }, 'does not take a value')
    expect_parse_error(spec, { '-z' }, 'unknown option')
    expect_parse_error({ { name = 'required', type = 'string', required = true } }, {}, 'required option')
    expect_parse_error({ { name = 'bad', short = 'xx' } }, {}, 'one character')
    expect_parse_error({ { name = 'bad', type = true } }, {}, 'type must be a string or nil')
    expect_parse_error({ { name = 'bad', type = 'array', default = 'base' } }, {}, 'default must be an array table')
    expect_parse_error({ { name = 'bad', type = 'array', default = { 'base', 1 } } }, {}, 'default array item #2 must be a string')
    expect_parse_error({ { name = 'bad', type = 'array', default = { [1] = 'base', [3] = 'extra' } } }, {}, 'default array must not contain holes')
end)

print('cli tests passed')
