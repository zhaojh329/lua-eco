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

#include <stdlib.h>
#include <lualib.h>

#include "config.h"
#include "list.h"
#include "eco.h"

enum {
    ECO_WATCHER_IO,
    ECO_WATCHER_TIMER,
    ECO_WATCHER_CHILD,
    ECO_WATCHER_SIGNAL
};

struct eco_watcher {
    struct ev_timer tmr;
    union {
        struct ev_io io;
        struct ev_child child;
        struct ev_signal signal;
    } w;
    struct eco_context *ctx;
    lua_State *co;
    int type;
};

#define ECO_WATCHER_MT "eco{watcher}"

static const char *obj_registry = "eco{obj}";
static const char *eco_context_registry = "eco-context";

static int eco_push_context(lua_State *L)
{
    lua_pushlightuserdata(L, &eco_context_registry);
    lua_rawget(L, LUA_REGISTRYINDEX);

    return 1;
}

static void eco_push_context_env(lua_State *L)
{
    eco_push_context(L);
    lua_getuservalue(L, -1);
    lua_remove(L, -2);
}

struct eco_context *eco_get_context(lua_State *L)
{
    struct eco_context *ctx;

    eco_push_context(L);

    ctx = lua_touserdata(L, -1);
    lua_pop(L, 1);

    return ctx;
}

static void eco_resume(lua_State *L, lua_State *co, int narg)
{
#if LUA_VERSION_NUM < 502
    int status = lua_resume(co, narg);
#else
    int status = lua_resume(co, L, narg);
#endif
    switch (status) {
    case 0: /* dead */
        eco_push_context_env(L);

        lua_pushlightuserdata(L, &obj_registry);
        lua_rawget(L, LUA_REGISTRYINDEX);
        lua_pushlightuserdata(L, co);
        lua_rawget(L, -2);
        lua_remove(L, -2);

        lua_pushnil(L);
        lua_rawset(L, -3);
        lua_pop(L, 1);
        break;

    case LUA_YIELD:
        break;

    default:
        lua_xmove(co, L, 1);
        fprintf(stderr, "%s\n", lua_tostring(L, -1));
        exit(1);
        break;
    }
}

static int eco_count(lua_State *L)
{
    int count = 0;

    lua_pushlightuserdata(L, &obj_registry);
    lua_rawget(L,            LUA_REGISTRYINDEX);

    lua_pushnil(L);
    while ( lua_next(L, -2) != 0 ) {
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

    lua_pushlightuserdata(L, &obj_registry);
    lua_rawget(L, LUA_REGISTRYINDEX);

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

    case ECO_WATCHER_CHILD:
        ev_child_stop(loop, &watcher->w.child);
        break;

    case ECO_WATCHER_SIGNAL:
        ev_signal_stop(loop, &watcher->w.signal);
        break;

    default:
        break;
    }

    lua_pushboolean(co, false);
    lua_pushliteral(co, "timeout");
    eco_resume(watcher->ctx->L, co, 2);
}

static void eco_watcher_io_cb(struct ev_loop *loop, ev_io *w, int revents)
{
    struct eco_watcher *watcher = container_of(w, struct eco_watcher, w.io);
    lua_State *co = watcher->co;

    watcher->co = NULL;

    ev_io_stop(loop, w);
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

static int eco_watcher(lua_State *L)
{
    int type = luaL_checkinteger(L, 1);
    struct eco_watcher *w;

    switch (type) {
    case ECO_WATCHER_TIMER:
        w = lua_newuserdata(L, sizeof(struct eco_watcher));
        break;

    case ECO_WATCHER_IO: {
            int fd = luaL_checkinteger(L, 2);
            int ev = luaL_optinteger(L, 3, EV_READ);

            if (ev != EV_READ && ev != EV_WRITE)
                luaL_argerror(L, 3, "must be eco.READ or eco.WRITE");

            w = lua_newuserdata(L, sizeof(struct eco_watcher));
            ev_io_init(&w->w.io, eco_watcher_io_cb, fd, ev);
        }
        break;

    case ECO_WATCHER_CHILD: {
            int pid = luaL_checkinteger(L, 2);

            w = lua_newuserdata(L, sizeof(struct eco_watcher));
            ev_child_init(&w->w.child, eco_watcher_child_cb, pid, 0);
        }
        break;

    case ECO_WATCHER_SIGNAL: {
            int signal = luaL_checkinteger(L, 2);

            w = lua_newuserdata(L, sizeof(struct eco_watcher));
            ev_signal_init(&w->w.signal, eco_watcher_signal_cb, signal);
        }
        break;

    default:
        luaL_argerror(L, 1, "invalid type");
    }

    w->type = type;

    ev_init(&w->tmr, eco_watcher_timeout_cb);

    w->ctx = eco_get_context(L);
    w->co = NULL;

    lua_pushvalue(L, lua_upvalueindex(1));
    lua_setmetatable(L, -2);

    return 1;
}

static int eco_watcher_wait(lua_State *L)
{
    struct eco_watcher *w = luaL_checkudata(L, 1, ECO_WATCHER_MT);
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

    if (timeout > 0) {
        ev_timer_set(&w->tmr, timeout, 0);
        ev_timer_start(loop, &w->tmr);
    }

    switch (w->type) {
    case ECO_WATCHER_IO:
        ev_io_start(loop, &w->w.io);
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

    return lua_yield(L, 0);
}

static int eco_watcher_cancel(lua_State *L)
{
    struct eco_watcher *w = luaL_checkudata(L, 1, ECO_WATCHER_MT);
    struct ev_loop *loop = w->ctx->loop;
    lua_State *co = w->co;

    if (!co)
        return 0;

    switch (w->type)
    {
    case ECO_WATCHER_IO:
        ev_io_stop(loop, &w->w.io);
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

static const struct luaL_Reg eco_watcher_methods[] =  {
    {"wait", eco_watcher_wait},
    {"cancel", eco_watcher_cancel},
    {NULL, NULL}
};

static int luaopen_eco(lua_State *L)
{
    lua_pushlightuserdata(L, &obj_registry);
    lua_newtable(L);
    lua_createtable(L, 0, 1);
    lua_pushliteral(L, "v");
    lua_setfield(L, -2, "__mode");
    lua_setmetatable(L, -2);
    lua_rawset(L, LUA_REGISTRYINDEX);

    lua_newtable(L);

    lua_add_constant(L, "VERSION_MAJOR", ECO_VERSION_MAJOR);
    lua_add_constant(L, "VERSION_MINOR", ECO_VERSION_MINOR);
    lua_add_constant(L, "VERSION_PATCH", ECO_VERSION_PATCH);

    lua_pushliteral(L, ECO_VERSION_STRING);
    lua_setfield(L, -2, "VERSION");

    lua_pushcfunction(L, eco_count);
    lua_setfield(L, -2, "count");

    lua_pushcfunction(L, eco_unloop);
    lua_setfield(L, -2, "unloop");

    lua_pushcfunction(L, eco_run);
    lua_setfield(L, -2, "run");

    lua_pushcfunction(L, eco_id);
    lua_setfield(L, -2, "id");

    lua_pushcfunction(L, eco_push_context);
    lua_setfield(L, -2, "context");

    lua_add_constant(L, "IO", ECO_WATCHER_IO);
    lua_add_constant(L, "TIMER", ECO_WATCHER_TIMER);
    lua_add_constant(L, "CHILD", ECO_WATCHER_CHILD);
    lua_add_constant(L, "SIGNAL", ECO_WATCHER_SIGNAL);

    lua_add_constant(L, "READ", EV_READ);
    lua_add_constant(L, "WRITE", EV_WRITE);

    eco_new_metatable(L, ECO_WATCHER_MT, eco_watcher_methods);
    lua_pushcclosure(L, eco_watcher, 1);
    lua_setfield(L, -2, "watcher");

    return 1;
}

int main(int argc, char const *argv[])
{
    struct ev_loop *loop = EV_DEFAULT;
    const char *script = argv[1];
    struct eco_context *ctx;
    lua_State *L;
    int error;

    if (!script)
        return 0;

    signal(SIGPIPE, SIG_IGN);

    L = luaL_newstate();

    luaL_openlibs(L);

    luaopen_eco(L);
    lua_setglobal(L, "eco");

    lua_pushlightuserdata(L, &eco_context_registry);
    ctx = lua_newuserdata(L, sizeof(struct eco_context));
    lua_newtable(L);
    lua_setuservalue(L, -2);
    luaL_newmetatable(L, ECO_CTX_MT);
    lua_setmetatable(L, -2);
    lua_rawset(L, LUA_REGISTRYINDEX);

    ctx->loop = loop;
    ctx->L = L;

    lua_getglobal(L, "eco");
    lua_getfield(L, -1, "run");
    lua_remove(L, -2);

    error = luaL_loadfile(L, script) || lua_pcall(L, 1, 0, 0);
    if (error) {
        fprintf(stderr, "%s\n", lua_tostring(L, -1));
        goto err;
    }

    ev_run(loop, 0);

err:
    lua_close(L);

    return error;
}
