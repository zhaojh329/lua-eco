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

#ifndef __ECO_HELPER_H
#define __ECO_HELPER_H

#include <lauxlib.h>
#include <stdbool.h>
#include <stdint.h>

#ifndef likely
#define likely(x)   (__builtin_expect(((x) != 0), 1))
#endif

#ifndef unlikely
#define unlikely(x) (__builtin_expect(((x) != 0), 0))
#endif

#ifndef ARRAY_SIZE
#define ARRAY_SIZE(arr) (sizeof(arr) / sizeof((arr)[0]))
#endif

#define BIT(x) (1ULL << (x))

#if LUA_VERSION_NUM < 502
#define lua_rawlen lua_objlen
#endif

#if LONG_BIT == 64
#define lua_pushint lua_pushinteger
#define lua_pushuint lua_pushinteger
#else
#define lua_pushint lua_pushnumber
#define lua_pushuint lua_pushinteger
#endif

#define nl_socket_enable_seq_check(sk)                                      \
    do {                                                                    \
        nl_socket_modify_cb(sk, NL_CB_SEQ_CHECK, NL_CB_CUSTOM, NULL, NULL); \
    } while (0)

#define stack_dump(L)                                           \
    do {                                                        \
        int top = lua_gettop(L);                                \
        int i;                                                  \
                                                                \
        for (i = 1; i <= top; i++) {                            \
            int t = lua_type(L, i);                             \
            switch (t) {                                        \
            case LUA_TSTRING:                                   \
                printf("'%s'", lua_tostring(L, i));             \
                break;                                          \
            case LUA_TBOOLEAN:                                  \
                printf(lua_toboolean(L, i) ? "true" : "false"); \
                break;                                          \
            case LUA_TNUMBER:                                       \
                printf("%g", lua_tonumber(L, i));               \
                break;                                          \
            default:                                            \
                printf("%s", lua_typename(L, t));               \
                break;                                          \
            }                                                   \
            printf(" ");                                        \
        }                                                       \
        printf("\n");                                           \
    } while (0)

#endif

#define lua_add_constant(n, v)  \
    do {                        \
        lua_pushinteger(L, v);  \
        lua_setfield(L, -2, n); \
    } while (0)

static inline int lua_gettablelen(lua_State *L, int index)
{
    int cnt = 0;

    lua_pushnil(L);
    index -= 1;

    while (lua_next(L, index) != 0) {
        cnt++;
        lua_pop(L, 1);
    }

    return cnt;
}

static inline bool lua_table_is_array(lua_State *L)
{
    lua_Integer prv = 0;
    lua_Integer cur = 0;

    /* Find out whether table is array-like */
    for (lua_pushnil(L); lua_next(L, -2); lua_pop(L, 1)) {
#ifdef LUA_TINT
        if (lua_type(L, -2) != LUA_TNUMBER && lua_type(L, -2) != LUA_TINT) {
#else
        if (lua_type(L, -2) != LUA_TNUMBER) {
#endif
            lua_pop(L, 2);
            return false;
        }

        cur = lua_tointeger(L, -2);

        if ((cur - 1) != prv) {
            lua_pop(L, 2);
            return false;
        }

        prv = cur;
    }

    return true;
}

static inline void eco_new_metatable(lua_State *L, const struct luaL_Reg regs[])
{
    const struct luaL_Reg *reg;

    lua_newtable(L);
    lua_pushvalue(L, -1);
    lua_setfield(L, -2, "__index");

    reg = regs;

    while (reg->name) {
        lua_pushcfunction(L, reg->func);
        lua_setfield(L, -2, reg->name);
        reg++;
    }
}
