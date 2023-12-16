#!/usr/bin/env eco

local socket = require 'eco.socket'
local sys = require 'eco.sys'

sys.signal(sys.SIGINT, function()
    print('\nGot SIGINT, now quit')
    eco.unloop()
end)

local s, err = socket.listen_tcp(nil, 8080, { reuseaddr = true })
if not s then
    error(err)
end

print('listen...')

local cnt = 0

while true do
    local c, peer = s:accept()
    if not c then
        print(peer)
        os.exit()
    end

    cnt = cnt + 1

    print(cnt .. ': new connection:', cnt, peer.ipaddr, peer.port)

    eco.run(function(c)
        while true do
            local data, err = c:recv(100)
            if not data then
                if err ~= 'closed' then
                    print(err)
                end
                c:close()
                break
            end
            c:send(data)
        end
    end, c)
end
