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

#ifndef __ECO_BUFFER_H
#define __ECO_BUFFER_H

#include <stdbool.h>
#include <stddef.h>
#include <lauxlib.h>

#define ECO_BUFFER_MT "eco{buffer}"

struct eco_buffer {
    size_t size;
    size_t first;
    size_t last;
    luaL_Buffer sb;
    size_t slen;
    char data[0];
};

#define buffer_skip(b, n)           \
    do {                            \
        b->first += n;              \
        if (b->first >= b->last)    \
            b->first = b->last = 0; \
    } while(0)

#define buffer_length(b) (b->last - b->first)

#define buffer_data(b) (b->data + b->first)

#define buffer_room(b) (b->size - b->last)

#endif
