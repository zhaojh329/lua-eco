# Networking and Transport

## Module eco.socket
Object methods:
- getfd / close / closed / setoption / getsockname / getpeername
- bind / listen / connect / accept
- send / write / sendto / sendfile
- recv / read / recvfull / readfull / readuntil / recvfrom

Constructors and helpers:
- socket / socketpair
- tcp / tcp6 / udp / udp6 / icmp / icmp6
- unix / unix_dgram / netlink
- listen_tcp / connect_tcp / listen_udp / connect_udp
- listen_unix / connect_unix
- open_tun
- is_ip_address

## Module eco.ssl
- ssl.listen / ssl.connect
- ssl_client: send/write/sendfile/recv/read/readfull/readuntil/close
- ssl_server: accept/close

## Module eco.dns
- dns.query
- dns.type_name

## Module eco.net
- net.ping
- net.ping6

## Module eco.packet
Parsers:
- from_icmp / from_icmp6 / from_ip / from_ip6 / from_ether / from_radiotap
Constructors:
- icmp / icmp6 / udp / tcp / ip / arp / ether
Objects:
- ParsedPacket:next

## Generation Guidance
- Select the API family by capability first, then choose protocol-specific functions.
- Do not mix unrelated capability paths as a substitute that merely appears to work.
- Network code must handle timeouts, disconnects, half-closes, and retry boundaries.
