#!/usr/bin/env eco

local ssl = require 'eco.ssl'
local sys = require 'eco.sys'

sys.signal(sys.SIGPIPE, function()end)

sys.signal(sys.SIGINT, function()
    print('\nGot SIGINT, now quit')
    eco.unloop()
end)

local s, err = ssl.listen(nil, 8080, { cert = 'cert.pem', key = 'key.pem' })
if not s then
    error(err)
end

print('listen...')

while true do
    local c, peer = s:accept()
    if not c then
        error(peer)
    end

    print('new connection:', peer.ipaddr, peer.port)

    eco.run(function(c)
        while true do
            local data, err = c:recv('*l')
            if not data then
                print(err)
                break
            end
            print('read:', data)
            c:send('I am eco:' .. data .. '\n')
        end
    end, c)
end
