cmake_minimum_required(VERSION 3.5)

project(lua-eco C)

include(FindPkgConfig)

list(APPEND CMAKE_MODULE_PATH "${CMAKE_SOURCE_DIR}/cmake/Modules/")

#set(CMAKE_VERBOSE_MAKEFILE ON)

# The version number.
set(ECO_VERSION_MAJOR 3)
set(ECO_VERSION_MINOR 1)
set(ECO_VERSION_PATCH 1)

find_package(Libev REQUIRED)

pkg_search_module(LUA53 lua-5.3)

if (NOT LUA53)
    find_path(LUA53_INCLUDE_DIRS lua.h PATH_SUFFIXES lua5.3)
    find_library(LUA53_LIBRARIES lua5.3)
endif()

if (NOT LUA53_INCLUDE_DIRS OR NOT LUA53_LIBRARIES)
    message(FATAL_ERROR "Liblua 5.3 is required.")
endif()

add_compile_options(-D_GNU_SOURCE -Os -Wall -Werror --std=gnu99 -fno-strict-aliasing)

# configure a header file to pass some of the CMake settings to the source code
configure_file(${CMAKE_CURRENT_SOURCE_DIR}/config.h.in ${CMAKE_CURRENT_BINARY_DIR}/config.h)

include_directories(${LUA53_INCLUDE_DIRS} ${LIBEV_INCLUDE_DIR})

set(LUA_INSTALL_PREFIX lib/lua/5.3)

option(ECO_SSL_SUPPORT "ssl" ON)
option(ECO_UBUS_SUPPORT "ubus" ON)
option(ECO_MQTT_SUPPORT "mqtt" ON)
option(ECO_SSH_SUPPORT "ssh" ON)

add_executable(eco eco.c)
target_link_libraries(eco PRIVATE ${LIBEV_LIBRARY} ${LUA53_LIBRARIES})
target_include_directories(eco PRIVATE ${CMAKE_CURRENT_BINARY_DIR})

add_library(time MODULE time.c)
target_link_libraries(time PRIVATE ${LIBEV_LIBRARY})
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

if (ECO_MQTT_SUPPORT)
    find_path(MOSQ_INCLUDE_DIRS mosquitto.h)
    find_library(MOSQ NAMES mosquitto)
    if (MOSQ_INCLUDE_DIRS AND MOSQ)
        add_library(mqtt MODULE mqtt.c)
        target_include_directories(mqtt PRIVATE ${MOSQ_INCLUDE_DIRS})
        target_link_libraries(mqtt PRIVATE ${MOSQ})
        set_target_properties(mqtt PROPERTIES OUTPUT_NAME mqtt PREFIX "")

        install(
            TARGETS mqtt
            DESTINATION ${LUA_INSTALL_PREFIX}/eco/core
        )

        install(
            FILES mqtt.lua
            DESTINATION ${LUA_INSTALL_PREFIX}/eco
        )
    else()
        message(WARNING "Not found libmosquitto. Skip build eco.mqtt")
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
    TARGETS eco
    DESTINATION bin
)

install(
    TARGETS log termios rtnl
    DESTINATION ${LUA_INSTALL_PREFIX}/eco
)

install(
    TARGETS sys file time bufio socket nl genl nl80211
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
    TARGETS sha1 md5
    DESTINATION ${LUA_INSTALL_PREFIX}/eco/hash
)

install(
    FILES time.lua sys.lua file.lua bufio.lua dns.lua socket.lua
        websocket.lua sync.lua nl.lua genl.lua ip.lua nl80211.lua
    DESTINATION ${LUA_INSTALL_PREFIX}/eco
)

install(
    FILES http/client.lua http/server.lua http/url.lua
    DESTINATION ${LUA_INSTALL_PREFIX}/eco/http
)
