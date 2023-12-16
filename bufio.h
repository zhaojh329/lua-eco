
/* SPDX-License-Identifier: MIT */
/*
 * Author: Jianhui Zhao <zhaojh329@gmail.com>
 */

#ifndef __ECO_BUFIO_H
#define __ECO_BUFIO_H

#include "eco.h"

struct eco_bufio {
    struct eco_context *eco;
    struct ev_timer tmr;
    struct ev_io io;
    lua_State *L;
    int fd;
    size_t n;   /* how many bytes to read currently */
    size_t pattern_len;
    const char *pattern; /* read pattern currently */
    double timeout;
    struct {
        uint8_t eof:1;
        uint8_t overtime:1;
    } flags;
    size_t size;
    size_t r, w;
    int (*fill)(struct eco_bufio *b, lua_State *L, lua_KContext ctx, lua_KFunction k);
    const char *eof_error;
    const char *error;
    const void *ctx;
    luaL_Buffer *b;
    char data[0];
};

#define buffer_skip(b, n)    \
    do {                     \
        b->r += n;           \
        if (b->r == b->w)    \
            b->r = b->w = 0; \
    } while(0)

#define buffer_slide(b) \
    do { \
        if (b->r > 0) { \
            memmove(b->data, b->data + b->r, b->w - b->r); \
            b->w -= b->r; \
            b->r = 0; \
        } \
    } while(0)

#define buffer_length(b) (b->w - b->r)
#define buffer_data(b) (b->data + b->r)
#define buffer_room(b) (b->size - b->w)

#endif
