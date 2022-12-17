/*
 * MIT License
 *
 * Copyright (c) 2022 Jianhui Zhao <zhaojh329@gmail.com>
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

#include <lauxlib.h>
#include <stdio.h>

#include "log/log.h"

static int lua_log_level(lua_State *L)
{
    int level = luaL_checkinteger(L, 1);

    log_level(level);

    return 0;
}

static void __lua_log(lua_State *L, int priority)
{
    static char buf[BUFSIZ];
    size_t room = BUFSIZ - 2;
    const char *filename = "";
    int line = -1;
    char *pos = buf;
    lua_Debug ar;
    int n, i;

    priority = LOG_PRI(priority);

    if (priority > __log_level__)
        return;

    n = lua_gettop(L);

    for (i = 1; i <= n && room > 0; i++) {
        const char *s;
        size_t len;

        s = lua_tolstring(L, i, &len);

        if (len > room)
            len = room;

        memcpy(pos, s, len);
        pos += len;
        room -= len;
    }

    *pos++ = '\n';
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

    lua_pushinteger(L, LOG_EMERG);
    lua_setfield(L, -2, "EMERG");

    lua_pushinteger(L, LOG_ALERT);
    lua_setfield(L, -2, "ALERT");

    lua_pushinteger(L, LOG_CRIT);
    lua_setfield(L, -2, "CRIT");

    lua_pushinteger(L, LOG_ERR);
    lua_setfield(L, -2, "ERR");

    lua_pushinteger(L, LOG_WARNING);
    lua_setfield(L, -2, "WARNING");

    lua_pushinteger(L, LOG_NOTICE);
    lua_setfield(L, -2, "NOTICE");

    lua_pushinteger(L, LOG_INFO);
    lua_setfield(L, -2, "INFO");

    lua_pushinteger(L, LOG_DEBUG);
    lua_setfield(L, -2, "DEBUG");

    lua_pushcfunction(L, lua_log_level);
    lua_setfield(L, -2, "level");

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
