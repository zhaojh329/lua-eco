# Encoding and Digests

## Module eco.encoding.base64
- encode
- decode

## Module eco.encoding.hex
- encode
- decode
- dump

## Module eco.hash.md5
- sum
- new

ctx methods:
- update
- final

## Module eco.hash.sha1
- sum
- new

ctx methods:
- update
- final

## Module eco.hash.sha256
- sum
- new

ctx methods:
- update
- final

## Module eco.hash.hmac
- new
- sum

hmac ctx methods:
- update
- final

## Review Focus
- Do not concatenate binary digests as if they were plain text.
- Choose raw bytes, hex, or base64 according to the use case.
