/* SPDX-License-Identifier: MIT */
/*
 * Author: Jianhui Zhao <zhaojh329@gmail.com>
 */

#ifndef __ECO_LUA_COMPAT_H
#define __ECO_LUA_COMPAT_H

#include <lauxlib.h>
#include <stdint.h>

#if LUA_VERSION_NUM < 502
#define lua_rawlen lua_objlen
#endif


#if LUA_VERSION_NUM <= 501

/** Backwards compatibility shims: */
#define lua_absindex(L, i)                              \
    ((i) > 0 || (i) <= LUA_REGISTRYINDEX ?              \
     (i) : lua_gettop(L) + (i) + 1)

#define lua_setuservalue(L, i) lua_setfenv((L), (i))

#define lua_getuservalue(L, i) lua_getfenv((L), (i))

#endif


#if LONG_BIT == 64
#define lua_pushint lua_pushinteger
#define lua_pushuint lua_pushinteger
#else
#define lua_pushint lua_pushnumber
#define lua_pushuint lua_pushinteger
#endif

#endif
