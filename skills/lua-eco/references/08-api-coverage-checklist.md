# API Coverage Checklist

This checklist ensures that the skill covers lua-eco public API families.

## Core
- eco

## Concurrency and Time
- eco.time
- eco.sync
- eco.channel

## System and IO
- eco.file
- eco.sys

## Networking Basics
- eco.socket
- eco.ssl
- eco.dns
- eco.net
- eco.packet

## Protocol Layer
- eco.http.url
- eco.http.client
- eco.http.server
- eco.websocket
- eco.mqtt

## Platform and Devices
- eco.ubus
- eco.uci
- eco.shared
- eco.log
- eco.termios
- eco.ssh

## Netlink Family
- eco.nl
- eco.genl
- eco.rtnl
- eco.ip
- eco.nl80211

## Encoding and Digests
- eco.encoding.base64
- eco.encoding.hex
- eco.hash.md5
- eco.hash.sha1
- eco.hash.sha256
- eco.hash.hmac

## Maintenance Flow
1. Update this checklist after adding or changing APIs.
2. Update references/90-public-api-manifest.md after adding or changing public APIs.
3. Run scripts/update-api-reference.sh to refresh references/91-api-quick-reference.md from LDoc search data.
4. Update references/95-high-risk-api-shapes.md when changing response objects, handler signatures, or return conventions for high-risk modules.
5. Run scripts/audit-public-api.sh to check source annotations, manifest coverage, and quick reference coverage.
6. Run scripts/check-routing-rules.sh to confirm routing guards and shape guards remain complete.
