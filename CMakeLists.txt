cmake_minimum_required(VERSION 3.5)

project(lua-eco C)

include(FindPkgConfig)

#set(CMAKE_VERBOSE_MAKEFILE ON)

# The version number.
set(ECO_VERSION_MAJOR 4)
set(ECO_VERSION_MINOR 0)
set(ECO_VERSION_PATCH 0)

pkg_search_module(LUA54 lua-5.4)

if (NOT LUA54)
    find_path(LUA54_INCLUDE_DIRS lua.h PATH_SUFFIXES lua5.4)
    find_library(LUA54_LIBRARIES lua5.4)
endif()

if (NOT LUA54_INCLUDE_DIRS OR NOT LUA54_LIBRARIES)
    message(FATAL_ERROR "Liblua 5.4 is required.")
endif()

add_compile_options(-DLUA_USE_LINUX -Os -Wall -Werror --std=gnu99 -fno-strict-aliasing)

# configure a header file to pass some of the CMake settings to the source code
configure_file(${CMAKE_CURRENT_SOURCE_DIR}/config.h.in ${CMAKE_CURRENT_BINARY_DIR}/config.h)

include_directories(${LUA54_INCLUDE_DIRS} ${CMAKE_CURRENT_SOURCE_DIR} ${CMAKE_CURRENT_BINARY_DIR})

set(LUA_INSTALL_PREFIX lib/lua/5.4)

option(ECO_SSL_SUPPORT "ssl" ON)
option(ECO_UBUS_SUPPORT "ubus" ON)
option(ECO_UCI_SUPPORT "uci" ON)
option(ECO_SSH_SUPPORT "ssh" ON)

add_executable(eco interpreter.c eco.c)
target_link_libraries(eco PRIVATE ${LUA54_LIBRARIES})

add_library(sync MODULE sync.c)
set_target_properties(sync PROPERTIES OUTPUT_NAME sync PREFIX "")

add_library(time MODULE time.c)
set_target_properties(time PROPERTIES OUTPUT_NAME time PREFIX "")

add_library(sys MODULE sys.c)
set_target_properties(sys PROPERTIES OUTPUT_NAME sys PREFIX "")

add_library(file MODULE file.c)
set_target_properties(file PROPERTIES OUTPUT_NAME file PREFIX "")

add_library(socket MODULE socket.c)
set_target_properties(socket PROPERTIES OUTPUT_NAME socket PREFIX "")

add_library(dns MODULE dns.c)
target_link_libraries(dns PRIVATE ${LUA54_LIBRARIES})
set_target_properties(dns PROPERTIES OUTPUT_NAME dns PREFIX "")

add_library(shared MODULE shared.c)
set_target_properties(shared PROPERTIES OUTPUT_NAME shared PREFIX "")

add_library(termios MODULE termios.c)
set_target_properties(termios PROPERTIES OUTPUT_NAME termios PREFIX "")

add_library(log MODULE log.c log/log.c)
set_target_properties(log PROPERTIES OUTPUT_NAME log PREFIX "")

add_library(base64 MODULE base64.c)
set_target_properties(base64 PROPERTIES OUTPUT_NAME base64 PREFIX "")

if (ECO_SSL_SUPPORT)
    add_subdirectory(ssl)
    if (SSL_SUPPORT)
        add_library(essl MODULE ssl.c)
        target_link_libraries(essl PRIVATE ${SSL_TARGET})
        set_target_properties(essl PROPERTIES OUTPUT_NAME ssl PREFIX "")

        install(
            TARGETS essl
            DESTINATION ${LUA_INSTALL_PREFIX}/eco/internal
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
            DESTINATION ${LUA_INSTALL_PREFIX}/eco/internal
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
            DESTINATION ${LUA_INSTALL_PREFIX}/eco/internal
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
    TARGETS log termios shared
    DESTINATION ${LUA_INSTALL_PREFIX}/eco
)

install(
    TARGETS sync sys file time log socket dns
    DESTINATION ${LUA_INSTALL_PREFIX}/eco/internal
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
    FILES time.lua sys.lua file.lua dns.lua socket.lua
        packet.lua mqtt.lua websocket.lua sync.lua channel.lua net.lua
    DESTINATION ${LUA_INSTALL_PREFIX}/eco
)

install(
    FILES http/client.lua http/server.lua http/url.lua
    DESTINATION ${LUA_INSTALL_PREFIX}/eco/http
)

add_subdirectory(nl)
add_subdirectory(hash)
