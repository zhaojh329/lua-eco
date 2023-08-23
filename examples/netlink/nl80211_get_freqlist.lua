#!/usr/bin/env eco

local nl80211 = require 'eco.nl80211'

local freqlist, err = nl80211.get_freqlist('phy0')
if not freqlist then
    print(err)
    return
end

for _, info in ipairs(freqlist) do
    io.write(info.freq .. ' MHz')
    io.write('(Band: ', info.band .. ' GHz, Channel: ', info.channel, ') ')

    local flags = table.keys(info.flags)
    if #flags > 0 then
        io.write('[', table.concat(flags, ', '), ']')
    end

    io.write('\n')
end
