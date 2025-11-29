local eco = require 'eco'
local time = require 'eco.time'

local n = 10

while n > 0 do
    eco.run(function ()
        eco.sleep(1)
    end)

    n = n - 1
end

time.at(3, function ()
    print(eco.count())
end)

eco.loop()

print('quit')
