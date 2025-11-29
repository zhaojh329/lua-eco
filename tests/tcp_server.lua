#!/usr/bin/env lua5.4

local socket = require 'eco.socket'
local sys = require 'eco.sys'
local eco = require 'eco'

sys.signal(sys.SIGINT, function()
    print('\nGot SIGINT, now quit')
    eco.unloop()
end)

local function handle_connection(c)
    while true do
        local data, err = c:recv(100)
        if not data then
            if err ~= 'eof' then
                print(err)
            end
            c:close()
            break
        end
        c:send(data)
    end
end

local s, err = socket.listen_tcp(nil, 8080, { reuseaddr = true })
if not s then
    error(err)
end

print('listen...')

local cnt = 0

eco.run(function()
    while true do
        local c, peer = s:accept()
        if not c then
            print(peer)
            os.exit()
        end

        cnt = cnt + 1

        print(cnt .. ': new connection:', cnt, peer.ipaddr, peer.port)

        eco.run(handle_connection, c)
    end
end)

eco.loop()
