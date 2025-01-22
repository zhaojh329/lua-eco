#!/usr/bin/env eco

local ubus = require 'eco.ubus'

local attr_types = {
    [ubus.ARRAY] = 'Array',
    [ubus.TABLE] = 'Table',
    [ubus.STRING] = 'String',
    [ubus.INT64] = 'Integer',
    [ubus.INT32] = 'Integer',
    [ubus.INT16] = 'Integer',
    [ubus.INT8] = 'Boolean',
    [ubus.DOUBLE] = 'Number'
}

local con, err = ubus.connect()
if not con then
    error(err)
end

for id, o in pairs(con:objects()) do
    print(string.format('"%s" @%08x', o, id))
    for method, signature in pairs(con:signatures(o)) do
        io.write(string.format('\t"%s":{', method))
        local comma = ''
        for k, v in pairs(signature) do
			io.write(string.format('%s"%s":"%s"', comma, k, attr_types[v] or 'unknown'))
            comma = ','
		end
        print('}')
    end
end

con:close()
