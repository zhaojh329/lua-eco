/* SPDX-License-Identifier: MIT */
/*
 * Author: Jianhui Zhao <zhaojh329@gmail.com>
 */

#ifndef __ECO_H
#define __ECO_H

#include <string.h>
#include <lauxlib.h>
#include <lua.h>
#include <ev.h>

#include "helper.h"

struct eco_context {
    struct ev_loop *loop;
    lua_State *L;
};

#ifndef ev_io_modify
#define ev_io_modify(ev,events_) do { (ev)->events = ((ev)->events & EV__IOFDSET) | (events_); } while (0)
#endif

const char **eco_get_context_registry();
const char **eco_get_obj_registry();

int eco_push_context(lua_State *L);
void eco_push_context_env(lua_State *L);
struct eco_context *eco_get_context(lua_State *L);

void eco_resume(lua_State *L, lua_State *co, int narg);

#endif
