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

#include "lua-compat.h"

#ifndef likely
#define likely(x)   (__builtin_expect(((x) != 0), 1))
#endif

#ifndef unlikely
#define unlikely(x) (__builtin_expect(((x) != 0), 0))
#endif

#define stack_dump(L)                                           \
    do {                                                        \
        int top = lua_gettop(L);                                \
        int i;                                                  \
        printf("--------stack dump--------\n");                 \
        for (i = 1; i <= top; i++) {                            \
            int t = lua_type(L, i);                             \
            printf("%2d: ", i);                                 \
            switch (t) {                                        \
            case LUA_TSTRING:                                   \
                printf("'%s'", lua_tostring(L, i));             \
                break;                                          \
            case LUA_TBOOLEAN:                                  \
                printf(lua_toboolean(L, i) ? "true" : "false"); \
                break;                                          \
            case LUA_TNUMBER:                                   \
                printf("%g", lua_tonumber(L, i));               \
                break;                                          \
            default:                                            \
                printf("%s", lua_typename(L, t));               \
                break;                                          \
            }                                                   \
            printf(" ");                                        \
        }                                                       \
        printf("\n");                                           \
        printf("++++++++++++++++++++++++++\n");                 \
    } while (0)

#define lua_add_constant(L, n, v)   \
    do {                            \
        lua_pushinteger(L, (v));    \
        lua_setfield(L, -2, (n));   \
    } while (0)

#define lua_gettablelen(L, idx)             \
    ({                                      \
        int index = lua_absindex(L, (idx)); \
        int cnt = 0;                        \
        lua_pushnil(L);                     \
        while (lua_next(L, index)) {        \
            cnt++;                          \
            lua_pop(L, 1);                  \
        }                                   \
        cnt;                                \
     })

#define lua_table_is_array(L, idx) lua_gettablelen(L, (idx)) == lua_rawlen(L, (idx))

static inline void eco_new_metatable(lua_State *L, const char *name, const struct luaL_Reg regs[])
{
    const struct luaL_Reg *reg;

    if (!luaL_newmetatable(L, name))
        return;

    lua_pushvalue(L, -1);
    lua_setfield(L, -2, "__index");

    if (!regs)
        return;

    reg = regs;

    while (reg->name) {
        lua_pushcfunction(L, reg->func);
        lua_setfield(L, -2, reg->name);
        reg++;
    }
}

#endif
