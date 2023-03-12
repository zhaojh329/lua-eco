/* SPDX-License-Identifier: MIT */
/*
 * Author: Jianhui Zhao <zhaojh329@gmail.com>
 */

#include <stdio.h>

#include "log/log.h"
#include "eco.h"

static int lua_log_set_level(lua_State *L)
{
    int level = luaL_checkinteger(L, 1);

    set_log_level(level);

    return 0;
}

static void __lua_log(lua_State *L, int priority)
{
    static char buf[BUFSIZ];
    size_t room = BUFSIZ - 1;
    const char *filename = "";
    int line = -1;
    char *pos = buf;
    lua_Debug ar;
    int n, i;

    priority = LOG_PRI(priority);

    if (priority > __log_level__)
        return;

    n = lua_gettop(L);

    for (i = 1; i <= n && room > 1; i++) {
        int t = lua_type(L, i);
        const char *s;
        size_t len;

        switch (t) {
        case LUA_TSTRING:
        case LUA_TNUMBER:
            s = lua_tolstring(L, i, &len);
            break;
        case LUA_TBOOLEAN:
            if (lua_toboolean(L, i)) {
                s = "true";
                len = 4;
            } else {
                s = "false";
                len = 5;
            }
            break;
        case LUA_TNIL:
            s = "nil";
            len = 3;
            break;
        default:
            continue;
        }

        if (i > 1) {
            *pos++ = '\t';
            room--;
        }

        if (len > room)
            len = room;

        memcpy(pos, s, len);
        pos += len;
        room -= len;
    }

    *pos = '\0';

    if (lua_getstack(L, 1, &ar)) {
        lua_getinfo(L, "Sl", &ar);
        if (ar.currentline > 0) {
            filename = ar.short_src;
            line = ar.currentline;
        }
    }

    ___log(filename, line, priority, "%s", buf);
}

static int lua_log_debug(lua_State *L)
{
    __lua_log(L, LOG_DEBUG);

    return 0;
}

static int lua_log_info(lua_State *L)
{
    __lua_log(L, LOG_INFO);

    return 0;
}

static int lua_log_err(lua_State *L)
{
    __lua_log(L, LOG_ERR);

    return 0;
}

static int lua_log(lua_State *L)
{
    int priority = lua_tointeger(L, 1);

    lua_remove(L, 1);

    __lua_log(L, priority);

    return 0;
}

static int lua_log_set_path(lua_State *L)
{
    const char *path = luaL_checkstring(L, 1);

    set_log_path(path);

    return 0;
}

int luaopen_eco_log(lua_State *L)
{
    lua_newtable(L);

    lua_add_constant(L, "EMERG", LOG_EMERG);
    lua_add_constant(L, "ALERT", LOG_ALERT);
    lua_add_constant(L, "CRIT", LOG_CRIT);
    lua_add_constant(L, "ERR", LOG_ERR);
    lua_add_constant(L, "WARNING", LOG_WARNING);
    lua_add_constant(L, "NOTICE", LOG_NOTICE);
    lua_add_constant(L, "INFO", LOG_INFO);
    lua_add_constant(L, "DEBUG", LOG_DEBUG);

    lua_pushcfunction(L, lua_log_set_level);
    lua_setfield(L, -2, "set_level");

    lua_pushcfunction(L, lua_log_debug);
    lua_setfield(L, -2, "debug");

    lua_pushcfunction(L, lua_log_info);
    lua_setfield(L, -2, "info");

    lua_pushcfunction(L, lua_log_err);
    lua_setfield(L, -2, "err");

    lua_pushcfunction(L, lua_log);
    lua_setfield(L, -2, "log");

    lua_pushcfunction(L, lua_log_set_path);
    lua_setfield(L, -2, "set_path");

    return 1;
}
