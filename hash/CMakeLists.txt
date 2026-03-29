add_library(sha1 MODULE sha1.c)
set_target_properties(sha1 PROPERTIES OUTPUT_NAME sha1 PREFIX "")

add_library(sha256 MODULE sha256.c)
set_target_properties(sha256 PROPERTIES OUTPUT_NAME sha256 PREFIX "")

add_library(md5 MODULE md5.c)
set_target_properties(md5 PROPERTIES OUTPUT_NAME md5 PREFIX "")

install(
    TARGETS sha1 sha256 md5
    DESTINATION ${LUA_INSTALL_PREFIX}/eco/hash
)

install(
    FILES hmac.lua
    DESTINATION ${LUA_INSTALL_PREFIX}/eco/hash
)
