/* SPDX-License-Identifier: MIT */
/*
 * Author: Jianhui Zhao <zhaojh329@gmail.com>
 */

/// @module eco.time

#include <sys/timerfd.h>
#include <string.h>
#include <errno.h>
#include <time.h>

#include "eco.h"

#define ECO_TIMERFD_MT "struct eco_timerfd *"

/**
 * Get current time
 *
 * @function now
 * @treturn number Current time in seconds.
 */
static int lua_now(lua_State *L)
{
    struct timespec ts;
    double seconds;

    clock_gettime(CLOCK_REALTIME, &ts);
    seconds = (double)ts.tv_sec + (double)ts.tv_nsec / 1e9;

    lua_pushnumber(L, seconds);

    return 1;
}

static int lua_timerfd_create(lua_State *L)
{
    int clock_id = luaL_checkinteger(L, 1);
    int fd;

    fd = timerfd_create(clock_id, TFD_NONBLOCK | TFD_CLOEXEC);
    if (fd < 0) {
        lua_pushnil(L);
        lua_pushstring(L, strerror(errno));
        return 2;
    }

    lua_pushinteger(L, fd);
    return 1;
}

static int lua_timerfd_settime(lua_State *L)
{
    int fd = luaL_checkinteger(L, 1);
    int flags = luaL_checkinteger(L, 2);
    double delay = luaL_checknumber(L, 3);
    double interval = lua_tonumber(L, 4);
    struct itimerspec its = {
        .it_value = {
            .tv_sec = delay,
            .tv_nsec = (delay - (long)delay) * 1000000000
        },
        .it_interval = {
            .tv_sec = interval,
            .tv_nsec = (interval - (long)interval) * 1000000000
        }
    };

    if (timerfd_settime(fd, flags, &its, NULL) < 0) {
        lua_pushnil(L);
        lua_pushstring(L, strerror(errno));
        return 2;
    }

    lua_pushboolean(L, true);
    return 1;
}

static const luaL_Reg funcs[] = {
    {"now", lua_now},
    {"timerfd_create", lua_timerfd_create},
    {"timerfd_settime", lua_timerfd_settime},
    {NULL, NULL}
};

int luaopen_eco_internal_time(lua_State *L)
{
    luaL_newlib(L, funcs);

    lua_add_constant(L, "CLOCK_MONOTONIC", CLOCK_MONOTONIC);
    lua_add_constant(L, "CLOCK_REALTIME", CLOCK_REALTIME);
    lua_add_constant(L, "TFD_TIMER_ABSTIME", TFD_TIMER_ABSTIME);

    return 1;
}
