#!/usr/bin/env eco

eco.panic_hook = function(...)
    print('panic_hook:')

    for _, v in ipairs({...}) do
        print(v)
    end
end

-- call a nil value
x()
