#!/usr/bin/env eco

local genl = require 'eco.genl'

local info, err = genl.get_family_byname('nlctrl')
if not info then
    print(err)
    return
end

for k, v in pairs(info) do
    if k == 'groups' then
        print('groups')
        for grp, id in pairs(v) do
            print('', grp, id)
        end
    else
        print(k, v)
    end
end
