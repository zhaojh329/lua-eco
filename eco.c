/* SPDX-License-Identifier: MIT */
/*
 * Author: Jianhui Zhao <zhaojh329@gmail.com>
 */

#include <sys/time.h>
#include <stdlib.h>
#include <lualib.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <time.h>

#include "config.h"
#include "eco.h"

enum {
    ECO_WATCHER_IO,
    ECO_WATCHER_ASYNC,
    ECO_WATCHER_TIMER,
    ECO_WATCHER_CHILD,
    ECO_WATCHER_SIGNAL
};

enum {
    ECO_FLAG_TIMER_PERIODIC = 1 << 0
};

struct eco_watcher {
    struct ev_timer tmr;
    union {
        struct ev_io io;
        struct ev_async async;
        struct ev_child child;
        struct ev_signal signal;
        struct ev_periodic periodic;
    } w;
    struct eco_context *ctx;
    lua_State *co;
    uint8_t flags;
    int type;
};

#define ECO_WATCHER_IO_MT     "eco{watcher.io}"
#define ECO_WATCHER_ASYNC_MT  "eco{watcher.async}"
#define ECO_WATCHER_TIMER_MT  "eco{watcher.timer}"
#define ECO_WATCHER_CHILD_MT  "eco{watcher.child}"
#define ECO_WATCHER_SIGNAL_MT "eco{watcher.signal}"

static int eco_count(lua_State *L)
{
    int count = 0;

    lua_rawgetp(L, LUA_REGISTRYINDEX, eco_get_obj_registry());

    lua_pushnil(L);
    while (lua_next(L, -2) != 0) {
        count++;
        lua_pop(L, 1);
    }
    lua_pushinteger(L, count);
    return 1;
}

static int eco_run(lua_State *L)
{
    int narg = lua_gettop(L);
    lua_State *co;

    luaL_checktype(L, 1, LUA_TFUNCTION);

    co = lua_newthread(L);

    lua_insert(L, 1);
    lua_xmove(L, co, narg);

    lua_rawgetp(L, LUA_REGISTRYINDEX, eco_get_obj_registry());

    lua_pushlightuserdata(L, co);
    lua_pushvalue(L, 1);
    lua_rawset(L, -3);
    lua_pop(L, 1);

    eco_push_context_env(L);
    lua_pushvalue(L, 1);
    lua_pushboolean(L, true);
    lua_rawset(L, -3);
    lua_pop(L, 1);

    eco_resume(L, co, narg - 1);

    return 0;
}

static int eco_unloop(lua_State *L)
{
    struct eco_context *ctx = eco_get_context(L);

    ev_break(ctx->loop, EVBREAK_ALL);

    return 0;
}

static int eco_id(lua_State *L)
{
    char buf[17];

    sprintf(buf, "%zx", (uintptr_t)L);
    lua_pushstring(L, buf);

    return 1;
}

static void eco_watcher_timeout_cb(struct ev_loop *loop, ev_timer *w, int revents)
{
    struct eco_watcher *watcher = container_of(w, struct eco_watcher, tmr);
    lua_State *co = watcher->co;

    watcher->co = NULL;

    switch (watcher->type) {
    case ECO_WATCHER_TIMER:
        lua_pushboolean(co, true);
        eco_resume(watcher->ctx->L, co, 1);
        return;

    case ECO_WATCHER_IO:
        ev_io_stop(loop, &watcher->w.io);
        break;

    case ECO_WATCHER_ASYNC:
        ev_async_stop(loop, &watcher->w.async);
        break;

    case ECO_WATCHER_CHILD:
        ev_child_stop(loop, &watcher->w.child);
        break;

    case ECO_WATCHER_SIGNAL:
        ev_signal_stop(loop, &watcher->w.signal);
        break;

    default:
        break;
    }

    lua_pushnil(co);
    lua_pushliteral(co, "timeout");
    eco_resume(watcher->ctx->L, co, 2);
}

static void eco_watcher_periodic_cb(struct ev_loop *loop, ev_periodic *w, int revents)
{
    struct eco_watcher *watcher = container_of(w, struct eco_watcher, w.periodic);
    lua_State *co = watcher->co;

    watcher->co = NULL;

    lua_pushboolean(co, true);
    eco_resume(watcher->ctx->L, co, 1);
}

static void eco_watcher_io_cb(struct ev_loop *loop, ev_io *w, int revents)
{
    struct eco_watcher *watcher = container_of(w, struct eco_watcher, w.io);
    lua_State *co = watcher->co;

    watcher->co = NULL;

    ev_io_stop(loop, w);
    ev_timer_stop(loop, &watcher->tmr);

    lua_pushinteger(co, revents);
    eco_resume(watcher->ctx->L, co, 1);
}

static void eco_watcher_async_cb(struct ev_loop *loop, struct ev_async *w, int revents)
{
    struct eco_watcher *watcher = container_of(w, struct eco_watcher, w.async);
    lua_State *co = watcher->co;

    watcher->co = NULL;

    ev_async_stop(loop, w);
    ev_timer_stop(loop, &watcher->tmr);

    lua_pushboolean(co, true);
    eco_resume(watcher->ctx->L, co, 1);
}

static void eco_watcher_child_cb(struct ev_loop *loop, struct ev_child *w, int revents)
{
    struct eco_watcher *watcher = container_of(w, struct eco_watcher, w.child);
    lua_State *co = watcher->co;
    int status = w->rstatus;

    watcher->co = NULL;

    ev_child_stop(loop, w);
    ev_timer_stop(loop, &watcher->tmr);

    lua_pushinteger(co, w->rpid);

    lua_newtable(co);

    if (WIFEXITED(status)) {
        lua_pushboolean(co, true);
        lua_setfield(co, -2, "exited");

        status = WEXITSTATUS(status);
    } else if (WIFSIGNALED(status)) {
        lua_pushboolean(co, true);
        lua_setfield(co, -2, "signaled");

        status = WTERMSIG(status);
    }

    lua_pushinteger(co, status);
    lua_setfield(co, -2, "status");

    eco_resume(watcher->ctx->L, co, 2);
}

static void eco_watcher_signal_cb(struct ev_loop *loop, struct ev_signal *w, int revents)
{
    struct eco_watcher *watcher = container_of(w, struct eco_watcher, w.signal);
    lua_State *co = watcher->co;

    watcher->co = NULL;

    ev_signal_stop(loop, w);
    ev_timer_stop(loop, &watcher->tmr);

    lua_pushboolean(co, true);
    eco_resume(watcher->ctx->L, co, 1);
}

static int eco_watcher_active(lua_State *L, const char *tname)
{
    struct eco_watcher *w = luaL_checkudata(L, 1, tname);
    lua_pushboolean(L, !!w->co);
    return 1;
}

static inline int eco_watcher_timer_active(lua_State *L)
{
    return eco_watcher_active(L, ECO_WATCHER_TIMER_MT);
}

static inline int eco_watcher_io_active(lua_State *L)
{
    return eco_watcher_active(L, ECO_WATCHER_IO_MT);
}

static inline int eco_watcher_async_active(lua_State *L)
{
    return eco_watcher_active(L, ECO_WATCHER_ASYNC_MT);
}

static inline int eco_watcher_child_active(lua_State *L)
{
    return eco_watcher_active(L, ECO_WATCHER_CHILD_MT);
}

static inline int eco_watcher_signal_active(lua_State *L)
{
    return eco_watcher_active(L, ECO_WATCHER_SIGNAL_MT);
}

static lua_CFunction eco_watcher_active_methods[] =  {
    [ECO_WATCHER_TIMER] = eco_watcher_timer_active,
    [ECO_WATCHER_IO] = eco_watcher_io_active,
    [ECO_WATCHER_ASYNC] = eco_watcher_async_active,
    [ECO_WATCHER_CHILD] = eco_watcher_child_active,
    [ECO_WATCHER_SIGNAL] = eco_watcher_signal_active
};

static int eco_watcher_wait(lua_State *L, const char *tname)
{
    struct eco_watcher *w = luaL_checkudata(L, 1, tname);
    struct ev_loop *loop = w->ctx->loop;
    double timeout = lua_tonumber(L, 2);

    if (w->co) {
        lua_pushboolean(L, false);
        lua_pushliteral(L, "busy");
        return 2;
    }

    if (timeout <= 0 && w->type == ECO_WATCHER_TIMER) {
        lua_pushboolean(L, true);
        return 1;
    }

    switch (w->type) {
    case ECO_WATCHER_IO:
        if (fcntl(w->w.io.fd, F_GETFL) < 0) {
            lua_pushboolean(L, false);
            lua_pushstring(L, strerror(errno));
            return 2;
        }
        ev_io_start(loop, &w->w.io);
        break;

    case ECO_WATCHER_ASYNC:
        ev_async_start(loop, &w->w.async);
        break;

    case ECO_WATCHER_CHILD:
        ev_child_start(loop, &w->w.child);
        break;

    case ECO_WATCHER_SIGNAL:
        ev_signal_start(loop, &w->w.signal);
        break;

    default:
        break;
    }

    w->co = L;

    if (timeout > 0) {
        if (w->flags & ECO_FLAG_TIMER_PERIODIC) {
            ev_periodic_set(&w->w.periodic, timeout, 0, NULL);
            ev_periodic_start(loop, &w->w.periodic);
        } else {
            ev_timer_set(&w->tmr, timeout, 0);
            ev_timer_start(loop, &w->tmr);
        }
    }

    return lua_yield(L, 0);
}

static inline int eco_watcher_timer_wait(lua_State *L)
{
    return eco_watcher_wait(L, ECO_WATCHER_TIMER_MT);
}

static inline int eco_watcher_io_wait(lua_State *L)
{
    return eco_watcher_wait(L, ECO_WATCHER_IO_MT);
}

static inline int eco_watcher_async_wait(lua_State *L)
{
    return eco_watcher_wait(L, ECO_WATCHER_ASYNC_MT);
}

static inline int eco_watcher_child_wait(lua_State *L)
{
    return eco_watcher_wait(L, ECO_WATCHER_CHILD_MT);
}

static inline int eco_watcher_signal_wait(lua_State *L)
{
    return eco_watcher_wait(L, ECO_WATCHER_SIGNAL_MT);
}

static lua_CFunction eco_watcher_wait_methods[] =  {
    [ECO_WATCHER_TIMER] = eco_watcher_timer_wait,
    [ECO_WATCHER_IO] = eco_watcher_io_wait,
    [ECO_WATCHER_ASYNC] = eco_watcher_async_wait,
    [ECO_WATCHER_CHILD] = eco_watcher_child_wait,
    [ECO_WATCHER_SIGNAL] = eco_watcher_signal_wait
};

static int eco_watcher_cancel(lua_State *L, const char *tname)
{
    struct eco_watcher *w = luaL_checkudata(L, 1, tname);
    struct ev_loop *loop = w->ctx->loop;
    lua_State *co = w->co;

    if (!co)
        return 0;

    switch (w->type) {
    case ECO_WATCHER_IO:
        ev_io_stop(loop, &w->w.io);
        break;

    case ECO_WATCHER_ASYNC:
        ev_async_stop(loop, &w->w.async);
        break;

    case ECO_WATCHER_CHILD:
        ev_child_stop(loop, &w->w.child);
        break;

    case ECO_WATCHER_SIGNAL:
        ev_signal_stop(loop, &w->w.signal);
        break;

    default:
        break;
    }

    w->co = NULL;

    ev_timer_stop(loop, &w->tmr);

    lua_pushboolean(co, false);
    lua_pushliteral(co, "canceled");
    eco_resume(w->ctx->L, co, 2);

    return 0;
}

static inline int eco_watcher_timer_cancel(lua_State *L)
{
    return eco_watcher_cancel(L, ECO_WATCHER_TIMER_MT);
}

static inline int eco_watcher_io_cancel(lua_State *L)
{
    return eco_watcher_cancel(L, ECO_WATCHER_IO_MT);
}

static inline int eco_watcher_async_cancel(lua_State *L)
{
    return eco_watcher_cancel(L, ECO_WATCHER_ASYNC_MT);
}

static inline int eco_watcher_child_cancel(lua_State *L)
{
    return eco_watcher_cancel(L, ECO_WATCHER_CHILD_MT);
}

static inline int eco_watcher_signal_cancel(lua_State *L)
{
    return eco_watcher_cancel(L, ECO_WATCHER_SIGNAL_MT);
}

static lua_CFunction eco_watcher_cancel_methods[] =  {
    [ECO_WATCHER_TIMER] = eco_watcher_timer_cancel,
    [ECO_WATCHER_IO] = eco_watcher_io_cancel,
    [ECO_WATCHER_ASYNC] = eco_watcher_async_cancel,
    [ECO_WATCHER_CHILD] = eco_watcher_child_cancel,
    [ECO_WATCHER_SIGNAL] = eco_watcher_signal_cancel
};

static int eco_watcher_async_send(lua_State *L)
{
    struct eco_watcher *w = luaL_checkudata(L, 1, ECO_WATCHER_ASYNC_MT);
    struct ev_loop *loop = w->ctx->loop;

    ev_async_send(loop, &w->w.async);

    return 0;
}

static struct eco_watcher *eco_watcher_new(lua_State *L, const char *mt)
{
    struct eco_watcher *w = lua_newuserdata(L, sizeof(struct eco_watcher));

    memset(w, 0, sizeof(struct eco_watcher));
    eco_new_metatable(L, mt, NULL);

    return w;
}

static struct eco_watcher *eco_watcher_timer(lua_State *L)
{
    bool periodic = lua_toboolean(L, 2);
    struct eco_watcher *w = eco_watcher_new(L, ECO_WATCHER_TIMER_MT);

    if (periodic) {
        w->flags |= ECO_FLAG_TIMER_PERIODIC;
        ev_init(&w->w.periodic, eco_watcher_periodic_cb);
    }

    return w;
}

static int eco_watcher_io_modify(lua_State *L)
{
    struct eco_watcher *w = luaL_checkudata(L, 1, ECO_WATCHER_IO_MT);
    int ev = luaL_checkinteger(L, 2);

    if (ev & ~(EV_READ | EV_WRITE))
        luaL_argerror(L, 3, "must be eco.READ or eco.WRITE or both them");

    ev_io_modify(&w->w.io, ev);

    return 0;
}

static int eco_watcher_io_getfd(lua_State *L)
{
    struct eco_watcher *w = luaL_checkudata(L, 1, ECO_WATCHER_IO_MT);

    lua_pushinteger(L, w->w.io.fd);

    return 1;
}

static struct eco_watcher *eco_watcher_io(lua_State *L)
{
    int fd = luaL_checkinteger(L, 2);
    int ev = luaL_optinteger(L, 3, EV_READ);
    struct eco_watcher *w;

    if (fcntl(fd, F_GETFL) < 0) {
        lua_pushnil(L);
        lua_pushstring(L, strerror(errno));
        return NULL;
    }

    if (ev & ~(EV_READ | EV_WRITE))
        luaL_argerror(L, 3, "must be eco.READ or eco.WRITE or both them");

    w = eco_watcher_new(L, ECO_WATCHER_IO_MT);
    ev_io_init(&w->w.io, eco_watcher_io_cb, fd, ev);

    lua_pushcfunction(L, eco_watcher_io_modify);
    lua_setfield(L, -2, "modify");

    lua_pushcfunction(L, eco_watcher_io_getfd);
    lua_setfield(L, -2, "getfd");

    return w;
}

static struct eco_watcher *eco_watcher_async(lua_State *L)
{
    struct eco_watcher *w = eco_watcher_new(L, ECO_WATCHER_ASYNC_MT);

    ev_async_init(&w->w.async, eco_watcher_async_cb);

    lua_pushcfunction(L, eco_watcher_async_send);
    lua_setfield(L, -2, "send");

    return w;
}

static struct eco_watcher *eco_watcher_child(lua_State *L)
{
    int pid = luaL_checkinteger(L, 2);
    struct eco_watcher *w = eco_watcher_new(L, ECO_WATCHER_CHILD_MT);

    ev_child_init(&w->w.child, eco_watcher_child_cb, pid, 0);

    return w;
}

static struct eco_watcher *eco_watcher_signal(lua_State *L)
{
    int signal = luaL_checkinteger(L, 2);
    struct eco_watcher *w = eco_watcher_new(L, ECO_WATCHER_SIGNAL_MT);

    ev_signal_init(&w->w.signal, eco_watcher_signal_cb, signal);

    return w;
}

static int eco_watcher(lua_State *L)
{
    int type = luaL_checkinteger(L, 1);
    struct eco_watcher *w;

    switch (type) {
    case ECO_WATCHER_TIMER:
        w = eco_watcher_timer(L);
        break;

    case ECO_WATCHER_IO:
        w = eco_watcher_io(L);
        break;

    case ECO_WATCHER_ASYNC:
        w = eco_watcher_async(L);
        break;

    case ECO_WATCHER_CHILD:
        w = eco_watcher_child(L);
        break;

    case ECO_WATCHER_SIGNAL:
        w = eco_watcher_signal(L);
        break;

    default:
        luaL_argerror(L, 1, "invalid type");
        return 0;
    }

    if (!w)
        return 2;

    w->type = type;

    ev_init(&w->tmr, eco_watcher_timeout_cb);

    w->ctx = eco_get_context(L);
    w->co = NULL;

    lua_pushcfunction(L, eco_watcher_active_methods[type]);
    lua_setfield(L, -2, "active");

    lua_pushcfunction(L, eco_watcher_wait_methods[type]);
    lua_setfield(L, -2, "wait");

    lua_pushcfunction(L, eco_watcher_cancel_methods[type]);
    lua_setfield(L, -2, "cancel");

    lua_setmetatable(L, -2);

    return 1;
}

static const luaL_Reg funcs[] = {
    {"context", eco_push_context},
    {"watcher", eco_watcher},
    {"count", eco_count},
    {"unloop", eco_unloop},
    {"run", eco_run},
    {"id", eco_id},
    {NULL, NULL}
};

static int luaopen_eco(lua_State *L)
{
    lua_newtable(L);
    lua_createtable(L, 0, 1);
    lua_pushliteral(L, "v");
    lua_setfield(L, -2, "__mode");
    lua_setmetatable(L, -2);
    lua_rawsetp(L, LUA_REGISTRYINDEX, eco_get_obj_registry());

    luaL_newlib(L, funcs);

    lua_add_constant(L, "VERSION_MAJOR", ECO_VERSION_MAJOR);
    lua_add_constant(L, "VERSION_MINOR", ECO_VERSION_MINOR);
    lua_add_constant(L, "VERSION_PATCH", ECO_VERSION_PATCH);

    lua_pushliteral(L, ECO_VERSION_STRING);
    lua_setfield(L, -2, "VERSION");

    lua_add_constant(L, "IO", ECO_WATCHER_IO);
    lua_add_constant(L, "ASYNC", ECO_WATCHER_ASYNC);
    lua_add_constant(L, "TIMER", ECO_WATCHER_TIMER);
    lua_add_constant(L, "CHILD", ECO_WATCHER_CHILD);
    lua_add_constant(L, "SIGNAL", ECO_WATCHER_SIGNAL);

    lua_add_constant(L, "READ", EV_READ);
    lua_add_constant(L, "WRITE", EV_WRITE);

    return 1;
}


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
    struct ev_loop *loop = EV_DEFAULT;
    struct eco_context *ctx;
    int error = 0;
    lua_State *L;
    int opt;

    signal(SIGPIPE, SIG_IGN);

    set_random_seed();

    L = luaL_newstate();

    luaL_openlibs(L);

    luaL_loadstring(L,
        "table.keys = function(t)"
        "local keys = {}"
        "for key in pairs(t) do "
        "keys[#keys + 1] = key "
        "end "
        "return keys "
        "end"
    );
    lua_pcall(L, 0, 0, 0);

    luaopen_eco(L);
    lua_setglobal(L, "eco");

    ctx = lua_newuserdata(L, sizeof(struct eco_context));
    lua_newtable(L);
    lua_setuservalue(L, -2);
    luaL_newmetatable(L, "eco{ctx}");
    lua_setmetatable(L, -2);
    lua_rawsetp(L, LUA_REGISTRYINDEX, eco_get_context_registry());

    ctx->loop = loop;
    ctx->L = L;

    lua_getglobal(L, "eco");
    lua_getfield(L, -1, "run");
    lua_remove(L, -2);

    while ((opt = getopt(argc, argv, "e:v")) != -1) {
        switch (opt) {
        case 'v':
            fprintf(stderr, LUA_RELEASE"\n");
            fprintf(stderr, "Lua-eco "ECO_VERSION_STRING"\n");
            goto err;

        case 'e':
            error = luaL_loadstring(L, optarg) || lua_pcall(L, 1, 0, 0);
            if (error) {
                fprintf(stderr, "%s\n", lua_tostring(L, -1));
                goto err;
            }
            goto run;

        default:
            show_usage(argv[0]);
            goto err;
        }
    }

    if (argc < 2)
        goto err;

    createargtable(L, argc, argv);

    error = luaL_loadfile(L, argv[1]) || lua_pcall(L, 1, 0, 0);
    if (error) {
        fprintf(stderr, "%s\n", lua_tostring(L, -1));
        goto err;
    }

run:
    ev_run(loop, 0);

err:
    lua_close(L);

    ev_default_destroy();

    return error;
}
