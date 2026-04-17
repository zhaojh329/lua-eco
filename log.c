/* SPDX-License-Identifier: MIT */
/*
 * Author: Jianhui Zhao <zhaojh329@gmail.com>
 */

/**
 * Logging utilities.
 *
 * This module provides simple logging helpers backed by syslog/stdout/file.
 *
 * - Default level: `INFO`
 * - Default flags: `FLAG_LF`
 *
 * Output backend selection:
 *
 * - If stdout is a TTY, logs go to stdout.
 * - Otherwise logs go to syslog.
 * - If @{log.set_path} is called with a non-empty path, logs are appended to that file.
 *
 * Log level constants (syslog priorities):
 *
 * - `EMERG`
 * - `ALERT`
 * - `CRIT`
 * - `ERR`
 * - `WARNING`
 * - `NOTICE`
 * - `INFO`
 * - `DEBUG`
 *
 * Flag constants:
 *
 * - `FLAG_LF` - append '\n'
 * - `FLAG_FILE` - filename:line
 * - `FLAG_PATH` - full path:line
 *
 * Notes about message arguments:
 *
 * - The logging functions accept varargs.
 * - Only `string`, `number`, `boolean` and `nil` values are rendered; other types are ignored.

 * @module eco.log
 */

#include <stdio.h>
#include <string.h>

#include "log/log.h"
#include "eco.h"

/**
 * Set current log level.
 *
 * Messages with priority greater than `level` are discarded.
 *
 * @function set_level
 * @tparam integer level One of the level constants (e.g. `log.INFO`, `log.DEBUG`).
 */
static int lua_log_set_level(lua_State *L)
{
    int level = luaL_checkinteger(L, 1);

    set_log_level(level);

    return 0;
}

static void lua_log_emit_lines(const char *filename, int line, int priority,
                               const char *message)
{
    const char *start = message;

    while (1) {
        const char *newline = strchr(start, '\n');
        size_t len;

        if (newline)
            len = newline - start;
        else
            len = strlen(start);

        if (len > 0 && start[len - 1] == '\r')
            len--;

        ___log(filename, line, priority, "%.*s", (int)len, start);

        if (!newline)
            break;

        start = newline + 1;
    }
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
            *pos++ = ' ';
            room--;
        }

        if (len > room)
            len = room;

        memcpy(pos, s, len);
        pos += len;
        room -= len;
    }

    *pos = '\0';

    if (__log_flags__ & LOG_FLAG_FILE || __log_flags__ & LOG_FLAG_PATH) {
        if (lua_getstack(L, 1, &ar)) {
            lua_getinfo(L, "Sl", &ar);
            if (ar.currentline > 0) {
                filename = ar.short_src;
                line = ar.currentline;
            }
        }
    }

    lua_log_emit_lines(filename, line, priority, buf);
}

/**
 * Log a DEBUG message.
 *
 * @function debug
 * @tparam[opt] any ... Values to log.
 */
static int lua_log_debug(lua_State *L)
{
    __lua_log(L, LOG_DEBUG);

    return 0;
}

/**
 * Log an INFO message.
 *
 * @function info
 * @tparam[opt] any ... Values to log.
 */
static int lua_log_info(lua_State *L)
{
    __lua_log(L, LOG_INFO);

    return 0;
}

/**
 * Log an ERR message.
 *
 * @function err
 * @tparam[opt] any ... Values to log.
 */
static int lua_log_err(lua_State *L)
{
    __lua_log(L, LOG_ERR);

    return 0;
}

/**
 * Log a message at a specific priority.
 *
 * @function log
 * @tparam integer priority One of the level constants (e.g. `log.WARNING`).
 * @tparam[opt] any ... Values to log.
 */
static int lua_log(lua_State *L)
{
    int priority = luaL_checkinteger(L, 1);

    lua_remove(L, 1);

    __lua_log(L, priority);

    return 0;
}

/**
 * Set log output file path.
 *
 * When set to a non-empty path, logs are appended to that file.
 * Passing an empty string resets output back to stdout/syslog.
 *
 * @function set_path
 * @tparam string path Output file path, or `''` to reset.
 */
static int lua_log_set_path(lua_State *L)
{
    const char *path = luaL_checkstring(L, 1);

    set_log_path(path);

    return 0;
}

/**
 * Set log flags.
 *
 * Combine flags using bitwise OR, e.g. `log.FLAG_LF | log.FLAG_FILE`.
 *
 * @function set_flags
 * @tparam integer flags Bitmask of `FLAG_*` constants.
 */
static int lua_log_set_flags(lua_State *L)
{
     int flags = luaL_checkinteger(L, 1);

    set_log_flags(flags);

    return 0;
}

/**
 * Set log roll size threshold in bytes.
 *
 * When current log file size reaches this threshold, it is rotated.
 * `0` disables log rolling.
 * Default is `100 * 1024` bytes.
 *
 * @function set_roll_size
 * @tparam integer size Maximum file size in bytes before rolling.
 */
static int lua_log_set_roll_size(lua_State *L)
{
    lua_Integer size = luaL_checkinteger(L, 1);

    luaL_argcheck(L, size >= 0, 1, "size must be >= 0");

    set_log_roll_size((size_t)size);

    return 0;
}

/**
 * Set max number of rolled files to keep.
 *
 * Values less than or equal to 0 are treated as library default.
 * Default is `10`.
 *
 * @function set_roll_count
 * @tparam integer count Max rolled file count to keep.
 */
static int lua_log_set_roll_count(lua_State *L)
{
    int count = luaL_checkinteger(L, 1);

    set_log_roll_count(count);

    return 0;
}

/**
 * Set syslog/file ident.
 *
 * This also affects the prefix when logging to file/stdout.
 *
 * @function set_ident
 * @tparam string ident Identifier string.
 */
static int lua_log_set_ident(lua_State *L)
{
    const char *ident = luaL_checkstring(L, 1);

    set_log_ident(ident);

    return 0;
}

static const luaL_Reg funcs[] = {
    {"set_level", lua_log_set_level},
    {"debug", lua_log_debug},
    {"info", lua_log_info},
    {"err", lua_log_err},
    {"log", lua_log},
    {"set_path", lua_log_set_path},
    {"set_flags", lua_log_set_flags},
    {"set_roll_size", lua_log_set_roll_size},
    {"set_roll_count", lua_log_set_roll_count},
    {"set_ident", lua_log_set_ident},
    {NULL, NULL}
};

int luaopen_eco_log(lua_State *L)
{
    luaL_newlib(L, funcs);

    lua_add_constant(L, "EMERG", LOG_EMERG);
    lua_add_constant(L, "ALERT", LOG_ALERT);
    lua_add_constant(L, "CRIT", LOG_CRIT);
    lua_add_constant(L, "ERR", LOG_ERR);
    lua_add_constant(L, "WARNING", LOG_WARNING);
    lua_add_constant(L, "NOTICE", LOG_NOTICE);
    lua_add_constant(L, "INFO", LOG_INFO);
    lua_add_constant(L, "DEBUG", LOG_DEBUG);

    lua_add_constant(L, "FLAG_LF", LOG_FLAG_LF);
    lua_add_constant(L, "FLAG_FILE", LOG_FLAG_FILE);
    lua_add_constant(L, "FLAG_PATH", LOG_FLAG_PATH);

    return 1;
}
