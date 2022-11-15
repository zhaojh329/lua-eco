cmake_minimum_required(VERSION 3.0)

project(lua-eco C)

include(FindPkgConfig)

list(APPEND CMAKE_MODULE_PATH "${CMAKE_SOURCE_DIR}/cmake/Modules/")

#set(CMAKE_VERBOSE_MAKEFILE ON)

# The version number.
set(ECO_VERSION_MAJOR 1)
set(ECO_VERSION_MINOR 0)
set(ECO_VERSION_PATCH 0)

find_package(Lua REQUIRED)
find_package(Libev REQUIRED)

pkg_search_module(LIBMNL libmnl)

add_compile_options(-D_GNU_SOURCE -O -Wall -Werror --std=gnu99)

# configure a header file to pass some of the CMake settings to the source code
configure_file(${CMAKE_CURRENT_SOURCE_DIR}/config.h.in ${CMAKE_CURRENT_BINARY_DIR}/config.h)

include_directories(${LUA_INCLUDE_DIR} ${LIBEV_INCLUDE_DIR})

option(ECO_LOG_SUPPORT "log facilities" ON)
option(ECO_SYS_SUPPORT "operating system facilities" ON)
option(ECO_SOCKET_SUPPORT "socket facilities" ON)
option(ECO_SSL_SUPPORT "ssl facilities" ON)
option(ECO_IW_SUPPORT "wireless utils facilities" ON)
option(ECO_FILE_SUPPORT "file facilities" ON)
option(ECO_UBUS_SUPPORT "ubus" ON)
option(ECO_DNS_SUPPORT "dns resolve" ON)
option(ECO_IP_SUPPORT "ip utils" ON)
option(ECO_HTTP_PARSER_SUPPORT "http-parser" ON)

set(TARGETS)

add_library(eco MODULE eco.c time.c)
target_link_libraries(eco PRIVATE ${LIBEV_LIBRARY})
set_target_properties(eco PROPERTIES OUTPUT_NAME eco PREFIX "")
target_include_directories(eco PRIVATE ${CMAKE_CURRENT_BINARY_DIR})

if (ECO_LOG_SUPPORT)
    add_library(log MODULE log.c log/log.c)
    set_target_properties(log PROPERTIES OUTPUT_NAME log PREFIX "")
    list(APPEND TARGETS log)
endif()

if (ECO_SYS_SUPPORT)
    add_library(sys MODULE sys.c)
    target_link_libraries(sys PRIVATE ${LIBEV_LIBRARY})
    set_target_properties(sys PROPERTIES OUTPUT_NAME sys PREFIX "")
    list(APPEND TARGETS sys)
endif()

if (ECO_SOCKET_SUPPORT)
    add_library(socket MODULE socket.c)
    target_link_libraries(socket PRIVATE ${LIBEV_LIBRARY})
    set_target_properties(socket PROPERTIES OUTPUT_NAME socket PREFIX "")
    list(APPEND TARGETS socket)
endif()

if (ECO_IW_SUPPORT)
    if (LIBMNL_FOUND)
        add_library(iw MODULE iw.c)
        target_include_directories(iw PRIVATE ${LIBMNL_INCLUDE_DIRS})
        target_link_libraries(iw PRIVATE ${LIBEV_LIBRARY} ${LIBMNL_LIBRARIES})
        set_target_properties(iw PROPERTIES OUTPUT_NAME iw PREFIX "")
        list(APPEND TARGETS iw)
    else()
        message(WARNING "Not found libmnl. Skip build eco.iw")
    endif()
endif()

if (ECO_SSL_SUPPORT)
    add_subdirectory(ssl)
    if (SSL_SUPPORT)
        add_library(ssl MODULE ssl.c)
        target_link_libraries(ssl PRIVATE ${LIBEV_LIBRARY} ${SSL_TARGET})
        set_target_properties(ssl PROPERTIES OUTPUT_NAME ssl PREFIX "")
        list(APPEND TARGETS ssl)
    else()
        message(WARNING "Not found any ssl library. Skip build eco.ssl")
    endif()
endif()

if (ECO_FILE_SUPPORT)
    add_library(file MODULE file.c)
    target_link_libraries(file PRIVATE ${LIBEV_LIBRARY})
    set_target_properties(file PROPERTIES OUTPUT_NAME file PREFIX "")
    list(APPEND TARGETS file)
endif()

if (ECO_UBUS_SUPPORT)
    find_library(UBUS NAMES ubus)
    if (UBUS)
        add_library(lubus MODULE ubus.c)
        target_link_libraries(lubus PRIVATE ${LIBEV_LIBRARY} ubus)
        set_target_properties(lubus PROPERTIES OUTPUT_NAME ubus PREFIX "")
        list(APPEND TARGETS lubus)
    else()
        message(WARNING "Not found libubus. Skip build eco.ubus")
    endif()
endif()

if (ECO_DNS_SUPPORT)
    add_library(dns MODULE dns.c)
    target_link_libraries(dns PRIVATE ${LIBEV_LIBRARY})
    set_target_properties(dns PROPERTIES OUTPUT_NAME dns PREFIX "")
    list(APPEND TARGETS dns)
endif()

if (ECO_IP_SUPPORT)
    if (LIBMNL_FOUND)
        add_library(ip MODULE ip.c)
        target_include_directories(ip PRIVATE ${LIBMNL_INCLUDE_DIRS})
        target_link_libraries(ip PRIVATE ${LIBEV_LIBRARY} ${LIBMNL_LIBRARIES})
        set_target_properties(ip PROPERTIES OUTPUT_NAME ip PREFIX "")
        list(APPEND TARGETS ip)
    else()
        message(WARNING "Not found libmnl. Skip build eco.ip")
    endif()
endif()

if (ECO_HTTP_PARSER_SUPPORT)
    find_library(LIBHTTP_PARSER NAMES http_parser)
    if (LIBHTTP_PARSER)
        add_library(lhttp_parser MODULE http-parser.c)
        target_link_libraries(lhttp_parser PRIVATE http_parser)
        set_target_properties(lhttp_parser PROPERTIES OUTPUT_NAME http-parser PREFIX "")
        list(APPEND TARGETS lhttp_parser)
    else()
        message(WARNING "Not found libhttp-parser. Skip build eco.http_parser")
    endif()
endif()

set(LUA_INSTALL_PREFIX lib/lua/${LUA_VERSION_MAJOR}.${LUA_VERSION_MINOR})

install(
    TARGETS eco
    DESTINATION ${LUA_INSTALL_PREFIX}
)

install(
    TARGETS ${TARGETS}
    DESTINATION ${LUA_INSTALL_PREFIX}/eco
)
