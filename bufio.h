/* SPDX-License-Identifier: MIT */
/*
 * Author: Jianhui Zhao <zhaojh329@gmail.com>
 */

#ifndef __ECO_BUFIO_H
#define __ECO_BUFIO_H

#include <stddef.h>

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

#endif
