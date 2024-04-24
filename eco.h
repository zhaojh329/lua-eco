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

#if defined(__linux__) || defined(__CYGWIN__)
#include <byteswap.h>
#include <endian.h>

#elif defined(__APPLE__)
#include <machine/endian.h>
#include <machine/byte_order.h>
#elif defined(__FreeBSD__)
#include <sys/endian.h>
#else
#include <machine/endian.h>
#endif

#ifndef __BYTE_ORDER
#define __BYTE_ORDER BYTE_ORDER
#endif
#ifndef __BIG_ENDIAN
#define __BIG_ENDIAN BIG_ENDIAN
#endif
#ifndef __LITTLE_ENDIAN
#define __LITTLE_ENDIAN LITTLE_ENDIAN
#endif

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
