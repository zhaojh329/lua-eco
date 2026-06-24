# Netlink Family

## Module eco.nl
- open

nlsocket methods:
- bind
- add_membership
- drop_membership
- send
- recv
- request_ack
- request_dump
- recv_messages
- close

## Module eco.genl
- get_family_byid
- get_family_byname
- get_family_id
- get_group_id

## Module eco.rtnl
Common constructors and parsers:
- rtgenmsg
- ifinfomsg
- ifaddrmsg
- rtmsg
- parse_ifinfomsg
- parse_ifaddrmsg
- parse_rtmsg

## Module eco.ip
link:
- set
- get

address:
- add
- del
- get

## Module eco.nl80211
Utility functions:
- ftype_name
- escape_ssid
- iftype_name
- width_name
- channel_type_name
- freq_to_channel
- freq_to_band
- phy_lookup

Interfaces and scanning:
- add_interface
- set_interface
- del_interface
- get_interface
- get_interfaces
- scan
- wait_event

Statistics and status:
- get_surveys
- get_noise
- get_station
- get_stations
- get_protocol_features
- get_freqlist
- get_link

## Review Focus
- Netlink callbacks must correctly handle message types and termination conditions.
- Device existence and parameter validity should be checked.
- Wireless scenarios must handle missing capabilities and platform differences.
