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

#include "buffer.h"
#include "eco.h"

static int eco_buffer_new(lua_State *L)
{
    int size = luaL_optinteger(L, 1, BUFSIZ);
    struct eco_buffer *b;

    b = lua_newuserdata(L, sizeof(struct eco_buffer) + size);
    memset(b, 0, sizeof(struct eco_buffer));
    lua_pushvalue(L, lua_upvalueindex(1));
    lua_setmetatable(L, -2);

    b->size = size;

    return 1;
}

static int eco_buffer_size(lua_State *L)
{
    struct eco_buffer *b = luaL_checkudata(L, 1, ECO_BUFFER_MT);

    lua_pushinteger(L, b->size);
    return 1;
}

static int eco_buffer_length(lua_State *L)
{
    struct eco_buffer *b = luaL_checkudata(L, 1, ECO_BUFFER_MT);

    lua_pushinteger(L, buffer_length(b));
    return 1;
}

static int eco_buffer_read(lua_State *L)
{
    struct eco_buffer *b = luaL_checkudata(L, 1, ECO_BUFFER_MT);
    size_t blen = buffer_length(b);
    size_t len = luaL_optinteger(L, 2, blen);

    if (len > blen)
        len = blen;

    lua_pushlstring(L, buffer_data(b), len);
    buffer_skip(b, len);

    return 1;
}

/*
** return value:
**  1: success
**  0: need more data
** -1: dest buffer is full
*/
static int eco_buffer_readline(lua_State *L)
{
    struct eco_buffer *b = luaL_checkudata(L, 1, ECO_BUFFER_MT);
    struct eco_buffer *bl = luaL_checkudata(L, 2, ECO_BUFFER_MT);
    size_t include = lua_toboolean(L, 3);
    const char *data = buffer_data(b);
    size_t blen = buffer_length(b);
    size_t pos = 0;
    int ret = 0;

    while (pos < blen && data[pos] != '\n') {
        if (!buffer_addchar(bl, data[pos])) {
            ret = -1;
            break;
        }
        pos++;
    }

    if (ret == 0 && pos < blen) {
        ret = 1;

        if (include && !buffer_addchar(bl, data[pos])) {
            ret = -1;
            goto skip;
        }

        pos++;
    }

skip:
    buffer_skip(b, pos);
    lua_pushinteger(L, ret);
    return 1;
}

static int eco_buffer_skip(lua_State *L)
{
    struct eco_buffer *b = luaL_checkudata(L, 1, ECO_BUFFER_MT);
    size_t len = luaL_checkinteger(L, 2);
    size_t blen = buffer_length(b);

    if (len > blen)
        len = blen;

    buffer_skip(b, len);

    return 0;
}

static int eco_buffer_append(lua_State *L)
{
    struct eco_buffer *b = luaL_checkudata(L, 1, ECO_BUFFER_MT);
    size_t len;
    const char *data = luaL_checklstring(L, 2, &len);
    size_t room = buffer_room(b);

    if (len > room)
        len = room;

    memmove(buffer_data(b) + b->last, data, len);
    b->last += len;
    lua_pushinteger(L, len);

    return 1;
}

static const struct luaL_Reg buffer_methods[] =  {
    {"size", eco_buffer_size},
    {"length", eco_buffer_length},
    {"read", eco_buffer_read},
    {"read_line", eco_buffer_readline},
    {"skip", eco_buffer_skip},
    {"append", eco_buffer_append},
    {NULL, NULL}
};

int luaopen_eco_buffer(lua_State *L)
{
    lua_newtable(L);

    eco_new_metatable(L, ECO_BUFFER_MT, buffer_methods);
    lua_pushcclosure(L, eco_buffer_new, 1);
    lua_setfield(L, -2, "new");

    return 1;
}
