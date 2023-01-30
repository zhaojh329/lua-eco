#!/usr/bin/env eco

local socket = require 'eco.socket'
local sys = require 'eco.sys'

sys.signal(sys.SIGINT, function()
    print('\nGot SIGINT, now quit')
    eco.unloop()
end)

local s, err = socket.listen_tcp(nil, 8080)
if not s then
    error(err)
end

print('listen...')

local cnt = 0

while true do
    local c, peer = s:accept()
    if not c then
        print(peer)
        break
    end

    cnt = cnt + 1

    print(cnt .. ': new connection:', cnt, peer.ipaddr, peer.port)

    eco.run(function(c)
        while true do
            local data, err = c:recv('*l')
            if not data then
                if err ~= 'closed' then
                    print(err)
                end
                c:close()
                break
            end
            c:send(data .. '\n')
        end
    end, c)
end
