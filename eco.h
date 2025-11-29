/* SPDX-License-Identifier: MIT */
/*
 * Author: Jianhui Zhao <zhaojh329@gmail.com>
 */

#ifndef __ECO_H
#define __ECO_H

#include <lauxlib.h>
#include <lualib.h>
#include <lua.h>

#include "helper.h"

#if defined(__linux__) || defined(__CYGWIN__)
#include <byteswap.h>
#include <endian.h>

#elif defined(__APPLE__)
#include <machine/endian.h>
#include <machine/byte_order.h>
#elif defined(__FreeBSD__)
#include <sys/endian.h>
#else
#include <machine/endian.h>
#endif

#ifndef __BYTE_ORDER
#define __BYTE_ORDER BYTE_ORDER
#endif
#ifndef __BIG_ENDIAN
#define __BIG_ENDIAN BIG_ENDIAN
#endif
#ifndef __LITTLE_ENDIAN
#define __LITTLE_ENDIAN LITTLE_ENDIAN
#endif


static inline void creat_metatable(lua_State *L, const char *name,
    const struct luaL_Reg *metatable, const struct luaL_Reg *methods)
{
    if (!luaL_newmetatable(L, name))
        return;

    if (metatable)
        luaL_setfuncs(L, metatable, 0);

    if (methods) {
        lua_newtable(L);
        luaL_setfuncs(L, methods, 0);
        lua_setfield(L, -2, "__index");
    }

    lua_pop(L, 1);
}

#endif
