#!/usr/bin/env eco

eco.panic_hook = function(err)
    print('panic_hook:', err)
end

-- call a nil value
x()
