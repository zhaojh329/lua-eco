/* SPDX-License-Identifier: MIT */
/*
 * Author: Jianhui Zhao <zhaojh329@gmail.com>
 */

#include <unistd.h>
#include <errno.h>
#include <fcntl.h>
#include <stdlib.h>

#include "bufio.h"

#define ECO_BUFIO_MT "eco{bufio}"

static bool eco_bufio_check_overtime(struct eco_bufio *b, lua_State *L)
{
    if (!b->flags.overtime)
        return false;

    if (b->b) {
        luaL_pushresult(b->b);
        lua_pop(L, 1);
        free(b->b);
    }

    b->flags.overtime = 0;
    lua_pushnil(L);
    lua_pushliteral(L, "timeout");

    return true;
}

static void ev_timer_cb(struct ev_loop *loop, ev_timer *w, int revents)
{
    struct eco_bufio *b = container_of(w, struct eco_bufio, tmr);

    ev_io_stop(loop, &b->io);

    b->flags.overtime = 1;

    eco_resume(b->eco->L, b->L, 0);
}

static void ev_io_read_cb(struct ev_loop *loop, ev_io *w, int revents)
{
    struct eco_bufio *b = container_of(w, struct eco_bufio, io);

    ev_io_stop(loop, w);
    ev_timer_stop(loop, &b->tmr);
    eco_resume(b->eco->L, b->L, 0);
}

static int eco_bufio_fill(struct eco_bufio *b, lua_State *L, lua_KContext ctx, lua_KFunction k)
{
    ssize_t ret;

    buffer_slide(b);

    if (buffer_room(b) == 0) {
        b->error = "buffer is full";
        return -1;
    }

again:
    ret = read(b->fd, b->data + b->w, buffer_room(b));
    if (unlikely(ret < 0)) {
        if (errno == EINTR)
            goto again;

        if (errno == EAGAIN) {
            b->L = L;

            if (b->timeout > 0) {
                ev_timer_set(&b->tmr, b->timeout, 0);
                ev_timer_start(b->eco->loop, &b->tmr);
            }

            ev_io_start(b->eco->loop, &b->io);
            return lua_yieldk(L, 0, ctx, k);
        }

        b->error = strerror(errno);
        return -1;
    }

    if (ret == 0) {
        b->flags.eof = 1;
        b->error = b->eof_error;
        return -1;
    }

    b->w += ret;

    return ret;
}

static int eco_bufio_new(lua_State *L)
{
    int fd = luaL_checkinteger(L, 1);
    const char *eof_error = NULL;
    const void *fill = NULL;
    const void *ctx = NULL;
    struct eco_bufio *b;
    int size = 0;
    int flags;

    flags = fcntl(fd, F_GETFL);
    if (flags < 0) {
        lua_pushnil(L);
        lua_pushstring(L, strerror(errno));
        return 2;
    }

    if (fcntl(fd, F_SETFL, flags | O_NONBLOCK)) {
        lua_pushnil(L);
        lua_pushstring(L, strerror(errno));
        return 2;
    }

    if (lua_istable(L, 2)) {
        lua_getfield(L, 2, "size");
        size = lua_tointeger(L, -1);

        lua_getfield(L, 2, "fill");
        fill = lua_topointer(L, -1);

        lua_getfield(L, 2, "ctx");
        ctx = lua_topointer(L, -1);

        lua_getfield(L, 2, "eof_error");
        eof_error = lua_tostring(L, -1);
    }

    if (size < 1)
        size = getpagesize();

    b = lua_newuserdata(L, sizeof(struct eco_bufio) + size);
    memset(b, 0, sizeof(struct eco_bufio));
    lua_pushvalue(L, lua_upvalueindex(1));
    lua_setmetatable(L, -2);

    b->eco = eco_get_context(L);
    b->size = size;
    b->fd = fd;
    b->fill = fill;
    b->ctx = ctx;
    b->eof_error = eof_error;

    if (!b->eof_error)
        b->eof_error = "eof";

    if (!b->fill)
        b->fill = eco_bufio_fill;

    ev_timer_init(&b->tmr, ev_timer_cb, 0.0, 0);
    ev_io_init(&b->io, ev_io_read_cb, fd, EV_READ);

    return 1;
}

static int eco_bufio_size(lua_State *L)
{
    struct eco_bufio *b = luaL_checkudata(L, 1, ECO_BUFIO_MT);

    lua_pushinteger(L, b->size);

    return 1;
}

static int eco_bufio_length(lua_State *L)
{
    struct eco_bufio *b = luaL_checkudata(L, 1, ECO_BUFIO_MT);

    lua_pushinteger(L, buffer_length(b));

    return 1;
}

static struct eco_bufio *read_check(lua_State *L)
{
    struct eco_bufio *b = luaL_checkudata(L, 1, ECO_BUFIO_MT);

    if (b->flags.eof) {
        lua_pushnil(L);
        lua_pushstring(L, b->eof_error);
        return NULL;
    }

    if (b->L) {
        lua_pushnil(L);
        lua_pushliteral(L, "busy reading");
        return NULL;
    }

    b->b = NULL;
    b->n = 0;
    b->pattern = NULL;

    return b;
}

static int lua_readk(lua_State *L, int status, lua_KContext ctx)
{
    struct eco_bufio *b = (struct eco_bufio *)ctx;
    const char *data = buffer_data(b);
    size_t blen = buffer_length(b);

    b->L = NULL;

    if (eco_bufio_check_overtime(b, L))
        return 2;

    if (b->pattern) {
        char pattern = *b->pattern;

        if (pattern == 'a') {
            if (!b->b) {
                if (buffer_room(b))
                    goto fill;

                b->b = malloc(sizeof(luaL_Buffer));
                if (!b->b) {
                    lua_pushnil(L);
                    lua_pushstring(L, strerror(errno));
                    return 2;
                }
                luaL_buffinit(L, b->b);
            }

            luaL_addlstring(b->b, data, blen);
            buffer_skip(b, blen);
        } else {
            int i;

            for (i = 0; i < blen; i++) {
                if (data[i] == '\n') {
                    lua_pushlstring(L, data, pattern == 'L' ? i + 1 : i);
                    buffer_skip(b, i + 1);
                    return 1;
                }
            }
        }
    } else {
        size_t n = b->n;

        if (!blen)
            goto fill;

        if (n > blen)
            n = blen;
        lua_pushlstring(L, buffer_data(b), n);
        buffer_skip(b, n);
        return 1;
    }

fill:
    if (b->fill(b, L, ctx, lua_readk) < 0) {
        if (b->pattern && *b->pattern == 'a') {
            if (b->b) {
                luaL_pushresult(b->b);
                free(b->b);

                if (b->flags.eof)
                    return 1;
                lua_pop(L, 1);
            } else if (b->flags.eof) {
                size_t blen = buffer_length(b);
                lua_pushlstring(L, buffer_data(b), blen);
                buffer_skip(b, blen);
                return 1;
            }
        }

        lua_pushnil(L);
        lua_pushstring(L, b->error);
        return 2;
    }

    return lua_readk(L, 0, ctx);
}

/*
  Reads according to the given pattern, which specify what to read.

  In case of success, it returns the data received; in case of error, it returns
  nil with a string describing the error.

  The available pattern are:
    'a': reads the whole file or reads from socket until the connection closed.
    'l': reads the next line skipping the end of line character.
    'L': reads the next line keeping the end-of-line character (if present).
    number: reads any data with up to this number of bytes.
*/
static int lua_read(lua_State *L)
{
    struct eco_bufio *b = read_check(L);

    if (!b)
        return 2;

    if (lua_isnumber(L, 2)) {
        b->n = lua_tointeger(L, 2);
        if (!b->n) {
            lua_pushliteral(L, "");
            return 1;
        }
    } else {
        const char *p = luaL_checkstring(L, 2);

        /* skip optional '*' (for compatibility) */
        if (*p == '*')
            p++;

        if (*p != 'l' && *p != 'L' && *p != 'a')
            return luaL_argerror(L, 2, "invalid pattern");

        b->pattern = p;
    }

    b->timeout = lua_tonumber(L, 3);

    return lua_readk(L, 0, (lua_KContext)b);
}

static int eco_bufio_peekk(lua_State *L, int status, lua_KContext ctx)
{
    struct eco_bufio *b = (struct eco_bufio *)ctx;
    size_t blen = buffer_length(b);
    size_t n = b->n;

    b->L = NULL;

    if (eco_bufio_check_overtime(b, L))
        return 2;

    if (blen < n)
        goto fill;

    lua_pushlstring(L, buffer_data(b), n);
    return 1;

fill:
    if (b->fill(b, L, ctx, eco_bufio_peekk) < 0) {
        lua_pushnil(L);
        lua_pushstring(L, b->error);
        return 2;
    }

    return eco_bufio_peekk(L, 0, ctx);
}

/* Returns the next n bytes without moving read position */
static int lua_peek(lua_State *L)
{
    struct eco_bufio *b = read_check(L);

    if (!b)
        return 2;

    b->n = luaL_checkinteger(L, 2);
    b->timeout = lua_tonumber(L, 3);

    if (b->n > b->size) {
        lua_pushnil(L);
        lua_pushliteral(L, "buffer is full");
        return 2;
    }

    return eco_bufio_peekk(L, 0, (lua_KContext)b);
}

static int lua_readfullk(lua_State *L, int status, lua_KContext ctx)
{
    struct eco_bufio *b = (struct eco_bufio *)ctx;
    size_t blen = buffer_length(b);
    size_t n = b->n;

    b->L = NULL;

    if (eco_bufio_check_overtime(b, L))
        return 2;

    if (!b->b) {
        if (blen < n)
            goto fill;

        lua_pushlstring(L, buffer_data(b), n);
        buffer_skip(b, n);
        return 1;
    }

    if (n > blen)
        n = blen;

    luaL_addlstring(b->b, buffer_data(b), n);
    buffer_skip(b, n);
    b->n -= n;

    if (!b->n) {
        luaL_pushresult(b->b);
        free(b->b);
        return 1;
    }

fill:
    if (b->fill(b, L, ctx, lua_readfullk) < 0) {
        if (b->b) {
            luaL_pushresult(b->b);
            lua_pop(L, 1);
            free(b->b);
        }
        lua_pushnil(L);
        lua_pushstring(L, b->error);
        return 2;
    }

    return lua_readfullk(L, 0, ctx);
}

/* Reads until it reads exactly desired size of data or an error occurs. */
static int lua_readfull(lua_State *L)
{
    struct eco_bufio *b = read_check(L);

    if (!b)
        return 2;

    b->n = luaL_checkinteger(L, 2);
    b->timeout = lua_tonumber(L, 3);

    if (b->n > b->size) {
        b->b = malloc(sizeof(luaL_Buffer));
        if (!b->b) {
            lua_pushnil(L);
            lua_pushstring(L, strerror(errno));
            return 2;
        }
        luaL_buffinit(L, b->b);
    }

    return lua_readfullk(L, 0, (lua_KContext)b);
}

static int lua_readuntilk(lua_State *L, int status, lua_KContext ctx)
{
    struct eco_bufio *b = (struct eco_bufio *)ctx;
    size_t pattern_len = b->pattern_len;
    size_t blen = buffer_length(b);
    void *data = buffer_data(b);
    void *pos;

    b->L = NULL;

    if (eco_bufio_check_overtime(b, L))
        return 2;

    pos = memmem(data, blen, b->pattern, pattern_len);
    if (pos) {
        lua_pushlstring(L, data, pos - data);
        lua_pushboolean(L, true);
        buffer_skip(b, pos - data + pattern_len);
        return 2;
    }

    if (blen > pattern_len) {
        lua_pushlstring(L, data, blen - pattern_len + 1);
        buffer_skip(b, blen - pattern_len + 1);
        return 1;
    }

    if (b->fill(b, L, ctx, lua_readuntilk) < 0) {
        lua_pushnil(L);
        lua_pushstring(L, b->error);
        return 2;
    }

    return lua_readuntilk(L, 0, ctx);
}

/*
 Read the data stream until it sees the specified pattern or an error occurs.
 The function can be called multiple times.
 It returns the received data on each invocation followed a boolean `true` if
 the specified pattern occurs.
*/
static int lua_readuntil(lua_State *L)
{
    struct eco_bufio *b = read_check(L);

    if (!b)
        return 2;

    b->pattern = luaL_checklstring(L, 2, &b->pattern_len);
    b->timeout = lua_tonumber(L, 3);

    luaL_argcheck(L, b->pattern_len > 0, 2, "Cannot be an empty string");

    return lua_readuntilk(L, 0, (lua_KContext)b);
}

static int lua_discardk(lua_State *L, int status, lua_KContext ctx)
{
    struct eco_bufio *b = (struct eco_bufio *)ctx;
    lua_Integer blen = buffer_length(b);
    size_t n = b->n;

    b->L = NULL;

    if (eco_bufio_check_overtime(b, L))
        return 2;

    if (n > blen)
        n = blen;

    buffer_skip(b, n);
    b->n -= blen;

    if (!b->n) {
        lua_pushboolean(L, true);
        return 1;
    }

    if (b->fill(b, L, ctx, lua_discardk) < 0) {
        lua_pushnil(L);
        lua_pushstring(L, b->error);
        return 2;
    }

    return lua_discardk(L, 0, ctx);
}

static int lua_discard(lua_State *L)
{
    struct eco_bufio *b = read_check(L);

    if (!b)
        return 2;

    b->n = luaL_checkinteger(L, 2);
    b->timeout = lua_tonumber(L, 3);

    return lua_discardk(L, 0, (lua_KContext)b);
}

static const struct luaL_Reg methods[] =  {
    {"size", eco_bufio_size},
    {"length", eco_bufio_length},
    {"read", lua_read},
    {"peek", lua_peek},
    {"readfull", lua_readfull},
    {"readuntil", lua_readuntil},
    {"discard", lua_discard},
    {NULL, NULL}
};

int luaopen_eco_bufio(lua_State *L)
{
    lua_newtable(L);

    eco_new_metatable(L, ECO_BUFIO_MT, methods);
    lua_pushcclosure(L, eco_bufio_new, 1);
    lua_setfield(L, -2, "new");

    return 1;
}
