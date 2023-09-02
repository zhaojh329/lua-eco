/* SPDX-License-Identifier: MIT */
/*
 * Author: Jianhui Zhao <zhaojh329@gmail.com>
 */

#include <lauxlib.h>
#include <stdint.h>

#define BASE64_PAD '='
#define BASE64DE_FIRST '+'
#define BASE64DE_LAST 'z'

static int lua_b64_encode(lua_State *L)
{
    static const char *Base64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=";
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
    static const uint8_t Base64[] = {
     /* nul, soh, stx, etx, eot, enq, ack, bel, */
        255, 255, 255, 255, 255, 255, 255, 255,
     /*  bs,  ht,  nl,  vt,  np,  cr,  so,  si, */
        255, 255, 255, 255, 255, 255, 255, 255,
     /* dle, dc1, dc2, dc3, dc4, nak, syn, etb, */
        255, 255, 255, 255, 255, 255, 255, 255,
     /* can,  em, sub, esc,  fs,  gs,  rs,  us, */
        255, 255, 255, 255, 255, 255, 255, 255,
     /*  sp, '!', '"', '#', '$', '%', '&', ''', */
        255, 255, 255, 255, 255, 255, 255, 255,
     /* '(', ')', '*', '+', ',', '-', '.', '/', */
        255, 255, 255,  62, 255, 255, 255,  63,
     /* '0', '1', '2', '3', '4', '5', '6', '7', */
        52,  53,  54,  55,  56,  57,  58,  59,
     /* '8', '9', ':', ';', '<', '=', '>', '?', */
        60,  61, 255, 255, 255, 255, 255, 255,
     /* '@', 'A', 'B', 'C', 'D', 'E', 'F', 'G', */
        255,   0,   1,  2,   3,   4,   5,    6,
     /* 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', */
        7,   8,   9,  10,  11,  12,  13,  14,
     /* 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', */
        15,  16,  17,  18,  19,  20,  21,  22,
     /* 'X', 'Y', 'Z', '[', '\', ']', '^', '_', */
        23,  24,  25, 255, 255, 255, 255, 255,
     /* '`', 'a', 'b', 'c', 'd', 'e', 'f', 'g', */
        255,  26,  27,  28,  29,  30,  31,  32,
     /* 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', */
        33,  34,  35,  36,  37,  38,  39,  40,
     /* 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', */
        41,  42,  43,  44,  45,  46,  47,  48,
     /* 'x', 'y', 'z', '{', '|', '}', '~', del, */
        49,  50,  51, 255, 255, 255, 255, 255
    };

    size_t inlen;
    const char *in = luaL_checklstring(L, 1, &inlen);
    uint8_t out[3] = {};
    int outlen = 0;
    luaL_Buffer b;
    int i, c;

    luaL_buffinit(L, &b);

    if (inlen & 0x3) {
        lua_pushnil(L);
        lua_pushliteral(L, "input is malformed");
        return 2;
    }

    for (i = 0; i < inlen; i++) {
        if (in[i] == '=') {
            outlen--;
            luaL_addlstring (&b, (const char *)out, outlen);
            break;
        }

        if (in[i] < BASE64DE_FIRST || in[i] > BASE64DE_LAST) {
            lua_pushnil(L);
            lua_pushliteral(L, "input is malformed");
            return 2;
        }

        c = Base64[(int)in[i]];
        if (c == 255) {
            lua_pushnil(L);
            lua_pushliteral(L, "input is malformed");
            return 2;
        }

        switch (i & 0x3) {
        case 0:
            out[0] = (c << 2) & 0xFF;
            outlen++;
            break;
        case 1:
            out[0] |= (c >> 4) & 0x3;
            out[1] = (c & 0xF) << 4;
            outlen++;
            break;
        case 2:
            out[1] |= (c >> 2) & 0xF;
            out[2] = (c & 0x3) << 6;
            outlen++;
            break;
        case 3:
            out[2] |= c;
            outlen = 0;

            luaL_addlstring(&b, (const char *)out, 3);
            break;
        }
    }

    luaL_pushresult(&b);
    return 1;
}

static const luaL_Reg funcs[] = {
    {"encode", lua_b64_encode},
    {"decode", lua_b64_decode},
    {NULL, NULL}
};

int luaopen_eco_encoding_base64(lua_State *L)
{
    luaL_newlib(L, funcs);
    return 1;
}
