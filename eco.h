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

static inline void creat_weak_table(lua_State *L, const char *mode, void *key)
{
    lua_newtable(L);
    lua_createtable(L, 0, 1);
    lua_pushstring(L, mode);
    lua_setfield(L, -2, "__mode");
    lua_setmetatable(L, -2);
    lua_rawsetp(L, LUA_REGISTRYINDEX, key);
}

static inline void set_obj(lua_State *L, void *key, int idx, void *p)
{
    idx = lua_absindex(L, idx);

    lua_rawgetp(L, LUA_REGISTRYINDEX, key);
    if (idx)
        lua_pushvalue(L, idx);
    else
        lua_pushnil(L);
    lua_rawsetp(L, -2, p);
    lua_pop(L, 1);
}

static inline void get_obj(lua_State *L, void *key, void *p)
{
    lua_rawgetp(L, LUA_REGISTRYINDEX, key);
    lua_rawgetp(L, -1, p);
    lua_remove(L, -2);
}

#endif
