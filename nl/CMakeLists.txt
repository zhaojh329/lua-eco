add_library(nl MODULE nl.c)
set_target_properties(nl PROPERTIES OUTPUT_NAME nl PREFIX "")

add_library(rtnl MODULE rtnl.c)
set_target_properties(rtnl PROPERTIES OUTPUT_NAME rtnl PREFIX "")

add_library(genl MODULE genl.c)
set_target_properties(genl PROPERTIES OUTPUT_NAME genl PREFIX "")

add_library(nl80211 MODULE nl80211.c)
set_target_properties(nl80211 PROPERTIES OUTPUT_NAME nl80211 PREFIX "")

install(
    TARGETS rtnl
    DESTINATION ${LUA_INSTALL_PREFIX}/eco
)

install(
    TARGETS nl genl nl80211
    DESTINATION ${LUA_INSTALL_PREFIX}/eco/internal
)

install(
    FILES nl.lua genl.lua ip.lua nl80211.lua
    DESTINATION ${LUA_INSTALL_PREFIX}/eco
)
