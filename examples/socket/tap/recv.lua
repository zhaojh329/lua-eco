#!/usr/bin/env eco

local socket = require 'eco.socket'
local packet = require 'eco.packet'
local link = require 'eco.ip'.link
local addr = require 'eco.ip'.address
local net = require 'eco.net'
local eco = require 'eco'

local function send_ping(name, ipaddr)
    eco.sleep(1)
    net.ping(ipaddr, { device = name })
end

local sock, name = socket.open_tun('tap0', { tap = true, no_pi = true })
if not sock then
    error('create tun socket failed: ' .. name)
end

print('tap device name:', name)

local ipaddr = '192.168.10.1'

local ok, err = addr.add(name, {
    address = ipaddr,
    prefix = 24,
    scope = 'global'
})
if not ok then
    error('add address failed: ' .. err)
end

link.set(name, { up = true })

eco.run(send_ping, name, '192.168.10.2')

local data, err = sock:recv(1500)
if not data then
    error('recv data failed: ' .. err)
end

local pkt, err = packet.from_ether(data)
if not pkt then
    error('parse packet failed: ' .. err)
end

print(pkt.name, pkt.source, pkt.dest)

while true do
    pkt = pkt:next()
    if not pkt then
        break
    end

    if pkt.name == 'ARP' then
        print(pkt.name, pkt.sha, pkt.sip, pkt.tha, pkt.tip)
    end
end
