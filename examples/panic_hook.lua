#!/usr/bin/env eco

eco.panic_hook = function(...)
    print('panic_hook:', ...)
end

-- call a nil value
x()
