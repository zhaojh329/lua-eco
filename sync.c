/* SPDX-License-Identifier: MIT */
/*
 * Author: Jianhui Zhao <zhaojh329@gmail.com>
 */

#include <sys/eventfd.h>
#include <string.h>
#include <errno.h>

#include "eco.h"

static int lua_eventfd(lua_State *L)
{
    int initval = luaL_checkinteger(L, 1);
    bool semaphore = lua_toboolean(L, 2);
    int flags = EFD_CLOEXEC | EFD_NONBLOCK;
    int fd;

    if (semaphore)
        flags |= EFD_SEMAPHORE;

    fd = eventfd(initval, flags);
    if (fd < 0)
        return push_errno(L, errno);

    lua_pushinteger(L, fd);
    return 1;
}

static const luaL_Reg funcs[] = {
    {"eventfd", lua_eventfd},
    {NULL, NULL}
};

int luaopen_eco_internal_sync(lua_State *L)
{
    luaL_newlib(L, funcs);

    return 1;
}
