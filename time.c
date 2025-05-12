/* SPDX-License-Identifier: MIT */
/*
 * Author: Jianhui Zhao <zhaojh329@gmail.com>
 */

#include "eco.h"

/* returns the Unix time, the number of seconds elapsed since January 1, 1970 UTC */
static int lua_ev_now(lua_State *L)
{
    struct ev_loop *loop = EV_DEFAULT;

    ev_now_update(loop);
    lua_pushnumber(L, ev_now(loop));

    return 1;
}

static const luaL_Reg funcs[] = {
    {"now", lua_ev_now},
    {NULL, NULL}
};

int luaopen_eco_core_time(lua_State *L)
{
    luaL_newlib(L, funcs);

    return 1;
}
