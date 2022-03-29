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

#include "eco.h"

struct eco_time_sleeper {
    struct eco_context *ctx;
    struct ev_timer tmr;
    lua_State *co;
};

static void eco_timer_cb(struct ev_loop *loop, ev_timer *w, int revents)
{
    struct eco_time_sleeper *s = container_of(w, struct eco_time_sleeper, tmr);

    eco_resume(s->ctx->L, s->co, 0);
}

static int eco_time_sleep(lua_State *L)
{
    struct eco_context *ctx = eco_check_context(L);
    struct ev_loop *loop = ctx->loop;
    double delay = lua_tonumber(L, 1);
    struct eco_time_sleeper *s;

    s = lua_newuserdata(L, sizeof(struct eco_time_sleeper));
    s->ctx = ctx;
    s->co = L;

    ev_timer_init(&s->tmr, eco_timer_cb, delay, 0.0);
    ev_timer_start(loop, &s->tmr);

    return lua_yield(L, 0);
}

static int eco_time_now(lua_State *L)
{
    struct eco_context *ctx = eco_check_context(L);
    struct ev_loop *loop = ctx->loop;
    lua_pushnumber(L, ev_now(loop));
    return 1;
}

int luaopen_eco_time(lua_State *L)
{
    lua_newtable(L);

    lua_pushcfunction(L, eco_time_sleep);
    lua_setfield(L, -2, "sleep");

    lua_pushcfunction(L, eco_time_now);
    lua_setfield(L, -2, "now");

    return 1;
}
