/* SPDX-License-Identifier: MIT */
/*
 * Author: Jianhui Zhao <zhaojh329@gmail.com>
 */

#include <unistd.h>
#include <errno.h>
#include <time.h>

#include "eco.h"

#define ECO_BUFIO_MT "eco{bufio}"

struct eco_bufio {
    size_t size;
    size_t r, w;
    char data[0];
};

#define buffer_skip(b, n)    \
    do {                     \
        b->r += n;           \
        if (b->r == b->w)    \
            b->r = b->w = 0; \
    } while(0)

#define buffer_length(b) (b->w - b->r)
#define buffer_data(b) (b->data + b->r)
#define buffer_room(b) (b->size - b->w)

static int eco_bufio_new(lua_State *L)
{
    int size = luaL_optinteger(L, 1, 4096);
    struct eco_bufio *b;

    b = lua_newuserdata(L, sizeof(struct eco_bufio) + size);
    memset(b, 0, sizeof(struct eco_bufio));
    lua_pushvalue(L, lua_upvalueindex(1));
    lua_setmetatable(L, -2);

    b->size = size;

    return 1;
}

static int eco_bufio_size(lua_State *L)
{
    struct eco_bufio *b = luaL_checkudata(L, 1, ECO_BUFIO_MT);
    lua_pushinteger(L, b->size);
    return 1;
}

static int eco_bufio_room(lua_State *L)
{
    struct eco_bufio *b = luaL_checkudata(L, 1, ECO_BUFIO_MT);
    lua_pushinteger(L, buffer_room(b));
    return 1;
}

static int eco_bufio_length(lua_State *L)
{
    struct eco_bufio *b = luaL_checkudata(L, 1, ECO_BUFIO_MT);
    lua_pushinteger(L, buffer_length(b));
    return 1;
}

static int eco_bufio_tail(lua_State *L)
{
    struct eco_bufio *b = luaL_checkudata(L, 1, ECO_BUFIO_MT);
    lua_pushlightuserdata(L, b->data + b->w);
    return 1;
}

static int eco_bufio_add(lua_State *L)
{
    struct eco_bufio *b = luaL_checkudata(L, 1, ECO_BUFIO_MT);
    size_t n = luaL_checkinteger(L, 2);

    b->w += n;
    return 1;
}

/* In case of success, it returns length, in case of error，it returns nil with an error code */
static int eco_bufio_fill(lua_State *L)
{
    struct eco_bufio *b = luaL_checkudata(L, 1, ECO_BUFIO_MT);
    int fd = luaL_checkinteger(L, 2);
    size_t room = buffer_room(b);
    int ret;

    if (!room) {
        lua_pushnil(L);
        lua_pushliteral(L, "buffer is full");
        return 2;
    }

    ret = read(fd, b->data + b->w, room);
    if (ret < 0) {
        lua_pushnil(L);
        lua_pushinteger(L, errno);
        return 2;
    }

    b->w += ret;

    lua_pushinteger(L, ret);
    return 1;
}

static int eco_bufio_read(lua_State *L)
{
    struct eco_bufio *b = luaL_checkudata(L, 1, ECO_BUFIO_MT);
    lua_Integer n = luaL_optinteger(L, 2, -1);
    lua_Integer blen = buffer_length(b);

    if (n < 0 || n > blen)
        n = blen;

    lua_pushlstring(L, buffer_data(b), n);
    buffer_skip(b, n);

    return 1;
}

static int eco_bufio_peek(lua_State *L)
{
    struct eco_bufio *b = luaL_checkudata(L, 1, ECO_BUFIO_MT);
    size_t len = luaL_checkinteger(L, 2);
    size_t blen = buffer_length(b);

    if (len > blen)
        len = blen;

    lua_pushlstring(L, buffer_data(b), len);
    return 1;
}

static int eco_bufio_skip(lua_State *L)
{
    struct eco_bufio *b = luaL_checkudata(L, 1, ECO_BUFIO_MT);
    size_t len = luaL_checkinteger(L, 2);
    size_t blen = buffer_length(b);

    if (len > blen)
        len = blen;

    buffer_skip(b, len);
    lua_pushinteger(L, len);
    return 1;
}

static int eco_bufio_index(lua_State *L)
{
    struct eco_bufio *b = luaL_checkudata(L, 1, ECO_BUFIO_MT);
    int c = luaL_checkinteger(L, 2);
    const char *data = buffer_data(b);
    size_t blen = buffer_length(b);
    int i;

    for (i = 0; i < blen; i++) {
        if (data[i] == c) {
            lua_pushinteger(L, i);
            return 1;
        }
    }

    lua_pushnil(L);
    return 1;
}

static int eco_bufio_find(lua_State *L)
{
    struct eco_bufio *b = luaL_checkudata(L, 1, ECO_BUFIO_MT);
    size_t needlelen;
    const char *needle = luaL_checklstring(L, 2, &needlelen);
    const char *data = buffer_data(b);
    size_t blen = buffer_length(b);
    const char *pos;

    pos = memmem(data, blen, needle, needlelen);
    if (pos)
        lua_pushinteger(L, pos - data);
    else
        lua_pushnil(L);

    return 1;
}

static int eco_bufio_slide(lua_State *L)
{
    struct eco_bufio *b = luaL_checkudata(L, 1, ECO_BUFIO_MT);

    if (b->r > 0) {
        memmove(b->data, b->data + b->r, b->w - b->r);
        b->w -= b->r;
        b->r = 0;
    }

    return 0;
}

static const struct luaL_Reg buffer_methods[] =  {
    {"size", eco_bufio_size},
    {"room", eco_bufio_room},
    {"length", eco_bufio_length},
    {"tail", eco_bufio_tail},
    {"add", eco_bufio_add},
    {"fill", eco_bufio_fill},
    {"read", eco_bufio_read},
    {"peek", eco_bufio_peek},
    {"skip", eco_bufio_skip},
    {"index", eco_bufio_index},
    {"find", eco_bufio_find},
    {"slide", eco_bufio_slide},
    {NULL, NULL}
};

int luaopen_eco_core_bufio(lua_State *L)
{
    lua_newtable(L);

    eco_new_metatable(L, ECO_BUFIO_MT, buffer_methods);
    lua_pushcclosure(L, eco_bufio_new, 1);
    lua_setfield(L, -2, "new");

    return 1;
}
