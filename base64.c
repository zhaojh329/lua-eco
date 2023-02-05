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

#include <lauxlib.h>
#include <stdint.h>
#include <ctype.h>

static const char *Base64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=";

static const unsigned char base64_suffix_map[256] = {
    255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 253, 255,
    255, 253, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
    255, 255, 255, 255, 255, 255, 255, 255, 253, 255, 255, 255,
    255, 255, 255, 255, 255, 255, 255,  62, 255, 255, 255,  63,
    52,  53,  54,  55,  56,  57,  58,  59,  60,  61, 255, 255,
    255, 254, 255, 255, 255,   0,   1,   2,   3,   4,   5,   6,
    7,   8,   9,  10,  11,  12,  13,  14,  15,  16,  17,  18,
    19,  20,  21,  22,  23,  24,  25, 255, 255, 255, 255, 255,
    255,  26,  27,  28,  29,  30,  31,  32,  33,  34,  35,  36,
    37,  38,  39,  40,  41,  42,  43,  44,  45,  46,  47,  48,
    49,  50,  51, 255, 255, 255, 255, 255, 255, 255, 255, 255,
    255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
    255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
    255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
    255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
    255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
    255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
    255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
    255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
    255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
    255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
    255, 255, 255, 255
};

static int lua_b64_encode(lua_State *L)
{
    size_t srclen;
    const uint8_t *input = (const uint8_t *)luaL_checklstring(L, 1, &srclen);
    luaL_Buffer b;

    luaL_buffinit(L, &b);

    while (srclen > 0) {
        int skip = 1;
        int i0 = input[0] >> 2;
        int i1 = (input[0] & 0x3) << 4;
        int i2 = 64;
        int i3 = 64;

        if (srclen > 1) {
            skip++;
            i1 += input[1] >> 4;
            i2 = (input[1] & 0xF) << 2;

            if (srclen > 2) {
                i2 += input[2] >> 6;
                i3 = input[2] & 0x3F;
                skip++;
            }
        }

        luaL_addchar(&b, Base64[i0]);
        luaL_addchar(&b, Base64[i1]);
        luaL_addchar(&b, Base64[i2]);
        luaL_addchar(&b, Base64[i3]);

        input += skip;
        srclen -= skip;
    }

    luaL_pushresult(&b);
    return 1;
}

static int lua_b64_decode(lua_State *L)
{
    size_t srclen;
    const char *input = luaL_checklstring(L, 1, &srclen);
    luaL_Buffer b;

    if (srclen == 0 || srclen % 4 != 0) {
        lua_pushnil(L);
        lua_pushliteral(L, "not a valid base64 encoded string");
        return 2;
    }

    luaL_buffinit(L, &b);
    luaL_prepbuffer(&b);

    int t = 0, y = 0;
    int c = 0;
    int g = 3;

    while (srclen-- > 0) {
        int pos = *input++;
        c = base64_suffix_map[pos];

        if (c == 255) {
            luaL_pushresult(&b);
            lua_pushliteral(L, "not a valid base64 encoded string");
            lua_pushnil(L);
            lua_replace(L, -3);
            return 2;
        }

        if (c == 253)
            continue;

        if (c == 254) {
            c = 0;
            g--;
        }

        t = (t << 6) | c;

        if (++y == 4) {
            luaL_addchar(&b, (t >> 16) & 0xff);
            if (g > 1)
                luaL_addchar(&b, (t >> 8) & 0xff);
            if (g > 2)
                luaL_addchar(&b, t & 0xff);
            y = t = 0;
        }
    }

    luaL_pushresult(&b);
    return 1;
}

int luaopen_eco_base64(lua_State *L)
{
    lua_newtable(L);

    lua_pushcfunction(L, lua_b64_encode);
    lua_setfield(L, -2, "encode");

    lua_pushcfunction(L, lua_b64_decode);
    lua_setfield(L, -2, "decode");

    return 1;
}
