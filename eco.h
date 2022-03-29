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

#ifndef __ECO_H
#define __ECO_H

#include <lauxlib.h>
#include <lua.h>
#include <ev.h>

#include "helper.h"
#include "list.h"

#define ECO_CONTEXT_KEY "__eco_ctx_key__"
#define ECO_CO_KEY "__eco_co_key__"

struct eco_context {
    struct ev_loop *loop;
    lua_State *L;
};

struct eco_buf {
    size_t len;
    size_t size;
    char data[0];
};

static inline struct eco_context *eco_get_context(lua_State *L)
{
    struct eco_context *ctx;

    lua_pushstring(L, ECO_CONTEXT_KEY);
    lua_rawget(L, LUA_REGISTRYINDEX);

    ctx = lua_touserdata(L, -1);
    lua_pop(L, 1);

    return ctx;
}

static inline struct eco_context *eco_check_context(lua_State *L)
{
    struct eco_context *ctx = eco_get_context(L);

    if (!ctx || ctx->L == L)
        luaL_error(L, "must be called in eco context");

    return ctx;
}

static inline void eco_resume(lua_State *L, lua_State *co, int narg)
{
#if LUA_VERSION_NUM < 502
    int status = lua_resume(co, narg);
#else
    int status = lua_resume(co, L, narg);
#endif
    switch (status) {
    case 0: /* dead */
        lua_pushstring(L, ECO_CO_KEY);
        lua_rawget(L, LUA_REGISTRYINDEX);   /* -1: objs table */
        lua_pushlightuserdata(L, co);       /* -2: objs table -1: key */
        lua_pushnil(L);                     /* -3: objs table -2: key -1: nil */
        lua_rawset(L, -3);
        lua_pop(L, 1);
        break;

    case LUA_YIELD:
        break;

    default:
        lua_xmove(co, L, 1);
        lua_error(L);
        break;
    }
}

#endif
