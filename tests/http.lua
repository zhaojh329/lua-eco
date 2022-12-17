#!/usr/bin/env eco

local socket = require 'eco.socket'
local sys = require 'eco.sys'

sys.signal(sys.SIGPIPE, function()end)

sys.signal(sys.SIGINT, function()
    print('\nGot SIGINT, now quit')
    eco.unloop()
end)

local s, err = socket.listen_tcp(nil, 8080)
if not s then
    error(err)
end

print('listen...')

while true do
    local c, peer = s:accept()
    if not c then
        print(peer)
        break
    end

    print('new connection:', peer.ipaddr, peer.port)

    eco.run(function(c)
        while true do
            while true do
                local data, err = c:recv('*l')
                if not data then
                    print(err)
                    c:close()
                    return
                end
                if data == '\r' then
                    break
                end
            end
            c:send('HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nhello')
        end
    end, c)
end
