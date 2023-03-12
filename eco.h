/* SPDX-License-Identifier: MIT */
/*
 * Author: Jianhui Zhao <zhaojh329@gmail.com>
 */

#ifndef __ECO_H
#define __ECO_H

#include <lauxlib.h>
#include <lua.h>
#include <ev.h>

#include "helper.h"

struct eco_context {
    struct ev_loop *loop;
    lua_State *L;
};

#define ECO_CTX_MT "eco{ctx}"

#endif
