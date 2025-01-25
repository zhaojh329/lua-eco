/* SPDX-License-Identifier: MIT */
/*
 * Author: Jianhui Zhao <zhaojh329@gmail.com>
 */

#include "eco.h"

/* returns the Unix time, the number of seconds elapsed since January 1, 1970 UTC */
static int lua_ev_now(lua_State *L)
{
    struct eco_context *ctx = eco_get_context(L);

    ev_now_update(ctx->loop);
    lua_pushnumber(L, ev_now(ctx->loop));

    return 1;
}

/*
 * pauses the current coroutine for at least the delay seconds.
 * A negative or zero delay causes sleep to return immediately.
 */
static int lua_sleep(lua_State *L)
{
    struct eco_context *ctx = eco_get_context(L);
    double delay = luaL_checknumber(L, 1);
    struct ev_timer *tmr;

    eco_push_context_env(L);
    lua_rawgetp(L, LUA_REGISTRYINDEX, eco_get_obj_registry());
    lua_pushlightuserdata(L, L);
    lua_rawget(L, -2); /* ctx_env, objs, co */
    lua_remove(L, -2); /* ctx_env, co */
    lua_rawget(L, -2); /* ctx_env, tmr_ptr */

    tmr = (struct ev_timer *)lua_topointer(L, -1);

    lua_pop(L, 2);

    ev_timer_set(tmr, delay, 0.0);
    ev_timer_start(ctx->loop, tmr);

    return lua_yield(L, 0);
}

static const luaL_Reg funcs[] = {
    {"now", lua_ev_now},
    {"sleep", lua_sleep},
    {NULL, NULL}
};

int luaopen_eco_core_time(lua_State *L)
{
    luaL_newlib(L, funcs);

    return 1;
}
