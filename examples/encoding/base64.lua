#!/usr/bin/env eco

local base64 = require 'eco.encoding.base64'

local msg = 'Hello, eco'

local encoded = base64.encode(msg)
print(encoded)

local decoded, err = base64.decode(encoded)
if not decoded then
    print('decode error:', err)
    return
end

print(decoded)
