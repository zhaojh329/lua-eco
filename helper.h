/* SPDX-License-Identifier: MIT */
/*
 * Author: Jianhui Zhao <zhaojh329@gmail.com>
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

#ifndef container_of
#define container_of(ptr, type, member)                             \
    ({                                                              \
        const __typeof__(((type *) NULL)->member) *__mptr = (ptr);	\
        (type *) ((char *) __mptr - offsetof(type, member));        \
    })
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
            case LUA_TLIGHTUSERDATA:                            \
                printf("%p", lua_topointer(L, i));              \
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
    if (!luaL_newmetatable(L, name))
        return;

    lua_pushvalue(L, -1);
    lua_setfield(L, -2, "__index");

    if (!regs)
        return;

    luaL_setfuncs(L, regs, 0);
}

#endif
