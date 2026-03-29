/* SPDX-License-Identifier: MIT */
/*
 * Author: Jianhui Zhao <zhaojh329@gmail.com>
 */

#include <sys/time.h>
#include <stdlib.h>
#include <lualib.h>
#include <unistd.h>
#include <getopt.h>
#include <fcntl.h>
#include <errno.h>
#include <time.h>

#include "config.h"
#include "eco.h"

/*
** Create the 'arg' table, which stores all arguments from the
** command line ('argv'). It should be aligned so that, at index 0,
** it has 'argv[script]', which is the script name. The arguments
** to the script (everything after 'script') go to positive indices;
** other arguments (before the script name) go to negative indices.
** If there is no script name, assume interpreter's name as base.
*/
static void createargtable(lua_State *L, int argc, char *const argv[])
{
    int i;

    lua_createtable(L, argc - 2, 2);

    for (i = 0; i < argc; i++) {
        lua_pushstring(L, argv[i]);
        lua_rawseti(L, -2, i - 1);
    }

    lua_setglobal(L, "arg");
}

static void show_usage(const char *progname)
{
    fprintf(stderr,
        "usage: %s [options] [script [args]].\n"
        "Available options are:\n"
        "  -h       show help message\n"
        "  -e stat  execute string 'stat'\n"
        "  -v       show version information\n"
        , progname);
}

static void set_random_seed()
{
    struct timeval t;

    gettimeofday(&t, NULL);
    srandom(t.tv_usec * t.tv_sec);
}

int main(int argc, char *const argv[])
{
    const char *exec_stat = NULL;
    int error = 0;
    lua_State *L;
    int eco_idx;
    int opt;

    while ((opt = getopt(argc, argv, "+hve:")) != -1) {
        switch (opt) {
        case 'v':
            fprintf(stderr, LUA_RELEASE"\n");
            fprintf(stderr, "Lua-eco "ECO_VERSION_STRING"\n");
            return 0;

        case 'e':
            exec_stat = optarg;
            break;

        default:
            show_usage(argv[0]);
            return 1;
        }
    }

    if (argc < 2 && !exec_stat) {
        show_usage(argv[0]);
        return 1;
    }

    set_random_seed();

    L = luaL_newstate();
    if (!L) {
        fprintf(stderr, "%s: cannot create state: not enough memory\n", argv[0]);
        return 1;
    }

    luaL_openlibs(L);

    lua_gc(L, LUA_GCRESTART);   /* start GC... */
    lua_gc(L, LUA_GCGEN, 0, 0); /* in generational mode */

    luaL_requiref(L, "eco", luaopen_eco, 1);
    eco_idx = lua_absindex(L, -1);

    lua_getfield(L, -1, "run");

    if (exec_stat) {
        error = luaL_loadstring(L, exec_stat) || lua_pcall(L, 1, 0, 0);
        if (error) {
            fprintf(stderr, "%s\n", lua_tostring(L, -1));
            goto err;
        }
        goto run;
    }

    createargtable(L, argc, argv);

    error = luaL_loadfile(L, argv[1]) || lua_pcall(L, 1, 0, 0);
    if (error) {
        fprintf(stderr, "%s\n", lua_tostring(L, -1));
        goto err;
    }

run:
    lua_getfield(L, eco_idx, "loop");
    lua_call(L, 0, 1);

    if (!lua_isnil(L, -1))
        return lua_error(L);

err:
    lua_close(L);

    return error;
}
