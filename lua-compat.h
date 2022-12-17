/*
 * MIT License
 *
 * Copyright (c) 2022 Jianhui Zhao <zhaojh329@gmail.com>
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
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
