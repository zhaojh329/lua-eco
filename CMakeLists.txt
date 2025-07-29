cmake_minimum_required(VERSION 3.5)

project(lua-eco C)

include(FindPkgConfig)

list(APPEND CMAKE_MODULE_PATH "${CMAKE_SOURCE_DIR}/cmake/Modules/")

#set(CMAKE_VERBOSE_MAKEFILE ON)

# The version number.
set(ECO_VERSION_MAJOR 3)
set(ECO_VERSION_MINOR 11)
set(ECO_VERSION_PATCH 0)

find_package(Libev REQUIRED)

pkg_search_module(LUA54 lua-5.4)

if (NOT LUA54)
    find_path(LUA54_INCLUDE_DIRS lua.h PATH_SUFFIXES lua5.4)
    find_library(LUA54_LIBRARIES lua5.4)
endif()

if (NOT LUA54_INCLUDE_DIRS OR NOT LUA54_LIBRARIES)
    message(FATAL_ERROR "Liblua 5.4 is required.")
endif()

add_compile_options(-D_GNU_SOURCE -DLUA_USE_LINUX -Os -Wall -Werror --std=gnu99 -fno-strict-aliasing)

# configure a header file to pass some of the CMake settings to the source code
configure_file(${CMAKE_CURRENT_SOURCE_DIR}/config.h.in ${CMAKE_CURRENT_BINARY_DIR}/config.h)

include_directories(${LUA54_INCLUDE_DIRS} ${LIBEV_INCLUDE_DIR})

set(LUA_INSTALL_PREFIX lib/lua/5.4)

option(ECO_SSL_SUPPORT "ssl" ON)
option(ECO_UBUS_SUPPORT "ubus" ON)
option(ECO_UCI_SUPPORT "uci" ON)
option(ECO_SSH_SUPPORT "ssh" ON)

add_library(libeco SHARED libeco.c)
set_target_properties(libeco PROPERTIES OUTPUT_NAME eco)
set_target_properties(libeco PROPERTIES VERSION
    ${ECO_VERSION_MAJOR}.${ECO_VERSION_MINOR}.${ECO_VERSION_PATCH} SOVERSION ${ECO_VERSION_MAJOR})

add_executable(eco eco.c)
target_link_libraries(eco PRIVATE libeco ${LIBEV_LIBRARY} ${LUA54_LIBRARIES})
target_include_directories(eco PRIVATE ${CMAKE_CURRENT_BINARY_DIR})

add_library(time MODULE time.c)
set_target_properties(time PROPERTIES OUTPUT_NAME time PREFIX "")

add_library(bufio MODULE bufio.c)
set_target_properties(bufio PROPERTIES OUTPUT_NAME bufio PREFIX "")

add_library(sys MODULE sys.c)
set_target_properties(sys PROPERTIES OUTPUT_NAME sys PREFIX "")

add_library(file MODULE file.c)
set_target_properties(file PROPERTIES OUTPUT_NAME file PREFIX "")

add_library(socket MODULE socket.c)
set_target_properties(socket PROPERTIES OUTPUT_NAME socket PREFIX "")

add_library(termios MODULE termios.c)
set_target_properties(termios PROPERTIES OUTPUT_NAME termios PREFIX "")

add_library(log MODULE log.c log/log.c)
set_target_properties(log PROPERTIES OUTPUT_NAME log PREFIX "")

add_library(base64 MODULE base64.c)
set_target_properties(base64 PROPERTIES OUTPUT_NAME base64 PREFIX "")

add_library(sha1 MODULE sha1.c)
set_target_properties(sha1 PROPERTIES OUTPUT_NAME sha1 PREFIX "")

add_library(sha256 MODULE sha256.c)
set_target_properties(sha256 PROPERTIES OUTPUT_NAME sha256 PREFIX "")

add_library(md5 MODULE md5.c)
set_target_properties(md5 PROPERTIES OUTPUT_NAME md5 PREFIX "")

add_library(nl MODULE nl.c)
set_target_properties(nl PROPERTIES OUTPUT_NAME nl PREFIX "")

add_library(rtnl MODULE rtnl.c)
set_target_properties(rtnl PROPERTIES OUTPUT_NAME rtnl PREFIX "")

add_library(genl MODULE genl.c)
set_target_properties(genl PROPERTIES OUTPUT_NAME genl PREFIX "")

add_library(nl80211 MODULE nl80211.c)
set_target_properties(nl80211 PROPERTIES OUTPUT_NAME nl80211 PREFIX "")

if (ECO_SSL_SUPPORT)
    add_subdirectory(ssl)
    if (SSL_SUPPORT)
        add_library(essl MODULE ssl.c)
        target_link_libraries(essl PRIVATE ${SSL_TARGET})
        set_target_properties(essl PROPERTIES OUTPUT_NAME ssl PREFIX "")

        install(
            TARGETS essl
            DESTINATION ${LUA_INSTALL_PREFIX}/eco/core
        )

        install(
            FILES ssl.lua
            DESTINATION ${LUA_INSTALL_PREFIX}/eco
        )
    else()
        message(WARNING "Not found any ssl library. Skip build eco.ssl")
    endif()
endif()

if (ECO_UBUS_SUPPORT)
    find_library(UBUS NAMES ubus)
    if (UBUS)
        add_library(lubus MODULE ubus.c)
        target_link_libraries(lubus PRIVATE ubus)
        set_target_properties(lubus PROPERTIES OUTPUT_NAME ubus PREFIX "")

        install(
            TARGETS lubus
            DESTINATION ${LUA_INSTALL_PREFIX}/eco/core
        )

        install(
            FILES ubus.lua
            DESTINATION ${LUA_INSTALL_PREFIX}/eco
        )
    else()
        message(WARNING "Not found libubus. Skip build eco.ubus")
    endif()
endif()

if (ECO_UCI_SUPPORT)
    find_library(UCI NAMES uci)
    if (UCI)
        add_library(luci MODULE uci.c)
        target_link_libraries(luci PRIVATE uci)
        set_target_properties(luci PROPERTIES OUTPUT_NAME uci PREFIX "")

        install(
            TARGETS luci
            DESTINATION ${LUA_INSTALL_PREFIX}/eco
        )
    else()
        message(WARNING "Not found libuci. Skip build eco.uci")
    endif()
endif()

if (ECO_SSH_SUPPORT)
    pkg_search_module(LIBSSH2 libssh2)
    if (LIBSSH2_FOUND)
        add_library(ssh MODULE ssh.c)
        target_link_libraries(ssh PRIVATE ${LIBSSH2_LIBRARIES})
        set_target_properties(ssh PROPERTIES OUTPUT_NAME ssh PREFIX "")

        install(
            TARGETS ssh
            DESTINATION ${LUA_INSTALL_PREFIX}/eco/core
        )

        install(
            FILES ssh.lua
            DESTINATION ${LUA_INSTALL_PREFIX}/eco
        )
    else()
        message(WARNING "Not found libssh2. Skip build eco.ssh")
    endif()
endif()

install(
    TARGETS libeco
    DESTINATION lib
)

install(
    TARGETS eco
    DESTINATION bin
)

install(
    TARGETS log termios rtnl bufio
    DESTINATION ${LUA_INSTALL_PREFIX}/eco
)

install(
    TARGETS sys file time nl genl socket nl80211
    DESTINATION ${LUA_INSTALL_PREFIX}/eco/core
)

install(
    TARGETS base64
    DESTINATION ${LUA_INSTALL_PREFIX}/eco/encoding
)

install(
    FILES hex.lua
    DESTINATION ${LUA_INSTALL_PREFIX}/eco/encoding
)

install(
    TARGETS sha1 sha256 md5
    DESTINATION ${LUA_INSTALL_PREFIX}/eco/hash
)

install(
    FILES hmac.lua
    DESTINATION ${LUA_INSTALL_PREFIX}/eco/hash
)

install(
    FILES time.lua sys.lua file.lua dns.lua socket.lua packet.lua mqtt.lua
        websocket.lua sync.lua channel.lua nl.lua genl.lua ip.lua nl80211.lua
        shared.lua
    DESTINATION ${LUA_INSTALL_PREFIX}/eco
)

install(
    FILES http/client.lua http/server.lua http/url.lua
    DESTINATION ${LUA_INSTALL_PREFIX}/eco/http
)
