/* SPDX-License-Identifier: MIT */
/*
 * Author: Jianhui Zhao <zhaojh329@gmail.com>
 */

#include "eco.h"

static int eco_time_now(lua_State *L)
{
    struct eco_context *ctx = luaL_checkudata(L, 1, ECO_CTX_MT);
    lua_pushnumber(L, ev_now(ctx->loop));
    return 1;
}

int luaopen_eco_core_time(lua_State *L)
{
    lua_newtable(L);

    lua_pushcfunction(L, eco_time_now);
    lua_setfield(L, -2, "now");

    return 1;
}
