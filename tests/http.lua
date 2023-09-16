#!/usr/bin/env eco

local http = require 'eco.http.server'
local sys = require 'eco.sys'

sys.signal(sys.SIGINT, function()
    print('\nGot SIGINT, now quit')
    eco.unloop()
end)

local function handler(con)
    con:send('Hello')
end

local srv, err = http.listen(nil, 8080, nil, handler)
if not srv then
    print(err)
    return
end
