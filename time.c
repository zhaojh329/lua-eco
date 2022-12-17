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

#include <errno.h>
#include <time.h>

#include "eco.h"

static int eco_time_now(lua_State *L)
{
    struct eco_context *ctx = luaL_checkudata(L, 1, ECO_CTX_MT);
    lua_pushnumber(L, ev_now(ctx->loop));
    return 1;
}

static int eco_time_sleep_sync(lua_State *L)
{
    double delay = luaL_checknumber(L, 1);
    struct timespec req = {
        .tv_sec = delay,
        .tv_nsec = (delay - (time_t)delay) * 1000000000
    };
    struct timespec rem;

again:
    if (nanosleep(&req, &rem)) {
        if (errno == EINTR)
            goto again;

        lua_pushboolean(L, false);
        lua_pushstring(L, strerror(errno));
        return 2;
    }

    lua_pushboolean(L, true);
    return 1;
}

int luaopen_eco_core_time(lua_State *L)
{
    lua_newtable(L);

    lua_pushcfunction(L, eco_time_now);
    lua_setfield(L, -2, "now");

    lua_pushcfunction(L, eco_time_sleep_sync);
    lua_setfield(L, -2, "sleep_sync");

    return 1;
}
