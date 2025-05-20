/* SPDX-License-Identifier: MIT */
/*
 * Author: Jianhui Zhao <zhaojh329@gmail.com>
 */

#include <sys/types.h>
#include <stdlib.h>
#include <unistd.h>
#include <errno.h>

#include "eco.h"

static const char *obj_registry = "eco{obj}";

const char **eco_get_obj_registry()
{
    return &obj_registry;
}

void eco_resume(lua_State *co, int narg)
{
    struct ev_loop *loop = EV_DEFAULT;
    lua_State *L = ev_userdata(loop);
    int status, nres;

    status = lua_resume(co, L, narg, &nres);
    switch (status) {
    case 0: /* dead */
        lua_rawgetp(L, LUA_REGISTRYINDEX, &obj_registry);
        lua_pushthread(co);
        lua_xmove(co, L, 1);
        lua_pushvalue(L, -1); /* ..., objs, co, co */
        lua_rawget(L, -3);    /* ..., objs, co, tmr_ptr */

        free((void *)lua_topointer(L, -1));
        lua_pop(L, 1);

        lua_pushnil(L);     /* ..., objs, co, nil */
        lua_rawset(L, -3);  /* objs[co] = nil */
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
