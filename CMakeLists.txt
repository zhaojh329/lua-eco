cmake_minimum_required(VERSION 3.0)

project(lua-eco C)

include(FindPkgConfig)

list(APPEND CMAKE_MODULE_PATH "${CMAKE_SOURCE_DIR}/cmake/Modules/")

#set(CMAKE_VERBOSE_MAKEFILE ON)

# The version number.
set(ECO_VERSION_MAJOR 2)
set(ECO_VERSION_MINOR 2)
set(ECO_VERSION_PATCH 0)

find_package(Lua REQUIRED)
find_package(Libev REQUIRED)

add_compile_options(-D_GNU_SOURCE -O -Wall -Werror --std=gnu99)

# configure a header file to pass some of the CMake settings to the source code
configure_file(${CMAKE_CURRENT_SOURCE_DIR}/config.h.in ${CMAKE_CURRENT_BINARY_DIR}/config.h)

include_directories(${LUA_INCLUDE_DIR} ${LIBEV_INCLUDE_DIR})

if ("${PLATFORM}" STREQUAL "openwrt")
    set(LUA_INSTALL_PREFIX /usr/lib/lua)
else()
    set(LUA_INSTALL_PREFIX lib/lua/${LUA_VERSION_MAJOR}.${LUA_VERSION_MINOR})
endif()

option(ECO_SSL_SUPPORT "ssl" ON)
option(ECO_UBUS_SUPPORT "ubus" ON)

add_executable(eco eco.c)
target_link_libraries(eco PRIVATE ${LIBEV_LIBRARY} ${LUA_LIBRARIES})
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

add_library(network MODULE network.c)
set_target_properties(network PROPERTIES OUTPUT_NAME network PREFIX "")

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

install(
    TARGETS eco
    DESTINATION bin
)

install(
    TARGETS log termios network
    DESTINATION ${LUA_INSTALL_PREFIX}/eco
)

install(
    TARGETS sys file time bufio socket
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
    TARGETS sha1
    DESTINATION ${LUA_INSTALL_PREFIX}/eco/crypto
)

install(
    FILES time.lua sys.lua file.lua bufio.lua dns.lua socket.lua url.lua http.lua websocket.lua mqtt.lua sync.lua bit.lua
    DESTINATION ${LUA_INSTALL_PREFIX}/eco
)
