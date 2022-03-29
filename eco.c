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

#include <stdlib.h>
#include <time.h>

#include "config.h"
#include "eco.h"

static int eco_run(lua_State *L)
{
    int narg = lua_gettop(L);
    lua_State *co;

    luaL_checktype(L, 1, LUA_TFUNCTION);

    co = lua_newthread(L);  /* 1:fun ... top:thread */
    lua_insert(L, 1);       /* 1:thread 2:fun ... */
    lua_xmove(L, co, narg); /* 1:thread */

    lua_pushstring(L, ECO_CO_KEY);
    lua_rawget(L, LUA_REGISTRYINDEX);   /* 1:thread 2: objs table */

    lua_pushlightuserdata(L, co);       /* 1:thread 2: objs table 3: key */
    lua_pushvalue(L, 1);                /* 1:thread 2: objs table 3: key 4:thread */
    lua_rawset(L, 2);                   /* 1:thread 2: objs table */
    lua_pop(L, 2);

    if (eco_get_context(L))
        eco_resume(L, co, narg - 1);

    return 0;
}

static int eco_loop(lua_State *L)
{
    struct eco_context *ctx = eco_get_context(L);

    ev_run(ctx->loop, 0);

    return 0;
}

static int eco_unloop(lua_State *L)
{
    struct eco_context *ctx = eco_get_context(L);

    if (ctx)
        ev_break(ctx->loop, EVBREAK_ALL);

    return 0;
}

static int eco_count(lua_State *L)
{
    int num = 0;

    lua_pushstring(L, ECO_CO_KEY);
    lua_rawget(L, LUA_REGISTRYINDEX);

    lua_pushnil(L);

    while (lua_next(L, -2)) {
        num++;
        lua_pop(L, 1);
    }

    lua_pop(L, 1);

    lua_pushinteger(L, num);

    return 1;
}

int luaopen_eco(lua_State *L)
{
    struct ev_loop *loop = EV_DEFAULT;
    struct eco_context *ctx;

    lua_pushstring(L, ECO_CONTEXT_KEY);
    ctx = lua_newuserdata(L, sizeof(struct eco_context));
    lua_rawset(L, LUA_REGISTRYINDEX);

    memset(ctx, 0, sizeof(struct eco_context));

    ctx->loop = loop;
    ctx->L = L;

    srand(time(NULL));

    /* create a table to store all eco */
    lua_pushstring(L, ECO_CO_KEY);
    lua_newtable(L);
    lua_rawset(L, LUA_REGISTRYINDEX);
    lua_pop(L, 1);

    lua_newtable(L);

    lua_add_constant("VERSION_MAJOR", ECO_VERSION_MAJOR);
    lua_add_constant("VERSION_MINOR", ECO_VERSION_MINOR);
    lua_add_constant("VERSION_PATCH", ECO_VERSION_PATCH);

    lua_pushliteral(L, ECO_VERSION_STRING);
    lua_setfield(L, -2, "VERSION");

    lua_pushcfunction(L, eco_loop);
    lua_setfield(L, -2, "loop");

    lua_pushcfunction(L, eco_unloop);
    lua_setfield(L, -2, "unloop");

    lua_pushcfunction(L, eco_count);
    lua_setfield(L, -2, "count");

    lua_pushcfunction(L, eco_run);
    lua_setfield(L, -2, "run");

    return 1;
}
