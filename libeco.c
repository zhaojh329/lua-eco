/* SPDX-License-Identifier: MIT */
/*
 * Author: Jianhui Zhao <zhaojh329@gmail.com>
 */

#include <sys/types.h>
#include <stdlib.h>
#include <unistd.h>
#include <errno.h>

#include "eco.h"

static const char *eco_context_registry = "eco-context";
static const char *obj_registry = "eco{obj}";

const char **eco_get_context_registry()
{
    return &eco_context_registry;
}

const char **eco_get_obj_registry()
{
    return &obj_registry;
}

int eco_push_context(lua_State *L)
{
    lua_rawgetp(L, LUA_REGISTRYINDEX, &eco_context_registry);

    return 1;
}

void eco_push_context_env(lua_State *L)
{
    eco_push_context(L);
    lua_getuservalue(L, -1);
    lua_remove(L, -2);
}

struct eco_context *eco_get_context(lua_State *L)
{
    struct eco_context *ctx;

    eco_push_context(L);

    ctx = lua_touserdata(L, -1);
    lua_pop(L, 1);

    return ctx;
}

void eco_resume(lua_State *L, lua_State *co, int narg)
{
#if LUA_VERSION_NUM > 503
    int nres;
    int status = lua_resume(co, L, narg, &nres);
#else
    int status = lua_resume(co, L, narg);
#endif
    switch (status) {
    case 0: /* dead */
        eco_push_context_env(L);
        lua_rawgetp(L, LUA_REGISTRYINDEX, &obj_registry);
        lua_pushlightuserdata(L, co);
        lua_rawget(L, -2);  /* ..., ctx_env, objs, co */
        lua_remove(L, -2);  /* ..., ctx_env, co */

        lua_pushvalue(L, -1); /* ..., ctx_env, co, co */
        lua_rawget(L, -3); /* ..., ctx_env, co, tmr_ptr */
        free((void *)lua_topointer(L, -1));
        lua_pop(L, 1);

        lua_pushnil(L);
        lua_rawset(L, -3);  /* ctx_env[co] = nil */
        lua_pop(L, 1);
        break;

    case LUA_YIELD:
        break;

    default:
        lua_xmove(co, L, 1);

        lua_getglobal(L, "eco");
        lua_getfield(L, -1, "panic_hook");
        lua_remove(L, -2);

        if (lua_isfunction(L, -1)) {
            lua_pushvalue(L, -2);
            lua_call(L, 1, 0);
        } else {
            fprintf(stderr, "%s\n", lua_tostring(L, -2));
        }

        exit(1);
        break;
    }
}
