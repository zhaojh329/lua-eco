/* SPDX-License-Identifier: MIT */
/*
 * Author: Jianhui Zhao <zhaojh329@gmail.com>
 *
 * Referenced from https://git.openwrt.org/?p=project/libubox.git;a=blob;f=md5.c
 */

#include <arpa/inet.h>
#include <stdbool.h>
#include <stdint.h>

#include "eco.h"

#define MD5_MT "eco{md5}"

struct md5_ctx {
    uint32_t lo, hi;
    uint32_t a, b, c, d;
    uint8_t buffer[64];
};

/*
 * The basic MD5 functions.
 *
 * F and G are optimized compared to their RFC 1321 definitions for
 * architectures that lack an AND-NOT instruction, just like in Colin Plumb's
 * implementation.
 */
#define F(x, y, z)			((z) ^ ((x) & ((y) ^ (z))))
#define G(x, y, z)			((y) ^ ((z) & ((x) ^ (y))))
#define H(x, y, z)			(((x) ^ (y)) ^ (z))
#define H2(x, y, z)			((x) ^ ((y) ^ (z)))
#define I(x, y, z)			((y) ^ ((x) | ~(z)))

/*
 * The MD5 transformation for all four rounds.
 */
#define STEP(f, a, b, c, d, x, t, s) \
    (a) += f((b), (c), (d)) + (x) + (t); \
    (a) = (((a) << (s)) | (((a) & 0xffffffff) >> (32 - (s)))); \
    (a) += (b);

/*
 * SET reads 4 input bytes in little-endian byte order and stores them
 * in a properly aligned word in host byte order.
 */
#if __BYTE_ORDER == __LITTLE_ENDIAN
#define SET(n) \
    (*(uint32_t *)&ptr[(n) * 4])
#define GET(n) \
    SET(n)
#else
#define SET(n) \
    (block[(n)] = \
    (uint32_t)ptr[(n) * 4] | \
    ((uint32_t)ptr[(n) * 4 + 1] << 8) | \
    ((uint32_t)ptr[(n) * 4 + 2] << 16) | \
    ((uint32_t)ptr[(n) * 4 + 3] << 24))
#define GET(n) \
    (block[(n)])
#endif

/*
 * This processes one or more 64-byte data blocks, but does NOT update
 * the bit counters.  There are no alignment requirements.
 */
static const void *body(struct md5_ctx *ctx, const void *data, unsigned long size)
{
    const unsigned char *ptr;
    uint32_t a, b, c, d;
    uint32_t saved_a, saved_b, saved_c, saved_d;
#if __BYTE_ORDER != __LITTLE_ENDIAN
    uint32_t block[16];
#endif

    ptr = (const unsigned char *)data;

    a = ctx->a;
    b = ctx->b;
    c = ctx->c;
    d = ctx->d;

    do {
        saved_a = a;
        saved_b = b;
        saved_c = c;
        saved_d = d;

        /* Round 1 */
        STEP(F, a, b, c, d, SET(0), 0xd76aa478, 7)
        STEP(F, d, a, b, c, SET(1), 0xe8c7b756, 12)
        STEP(F, c, d, a, b, SET(2), 0x242070db, 17)
        STEP(F, b, c, d, a, SET(3), 0xc1bdceee, 22)
        STEP(F, a, b, c, d, SET(4), 0xf57c0faf, 7)
        STEP(F, d, a, b, c, SET(5), 0x4787c62a, 12)
        STEP(F, c, d, a, b, SET(6), 0xa8304613, 17)
        STEP(F, b, c, d, a, SET(7), 0xfd469501, 22)
        STEP(F, a, b, c, d, SET(8), 0x698098d8, 7)
        STEP(F, d, a, b, c, SET(9), 0x8b44f7af, 12)
        STEP(F, c, d, a, b, SET(10), 0xffff5bb1, 17)
        STEP(F, b, c, d, a, SET(11), 0x895cd7be, 22)
        STEP(F, a, b, c, d, SET(12), 0x6b901122, 7)
        STEP(F, d, a, b, c, SET(13), 0xfd987193, 12)
        STEP(F, c, d, a, b, SET(14), 0xa679438e, 17)
        STEP(F, b, c, d, a, SET(15), 0x49b40821, 22)

        /* Round 2 */
        STEP(G, a, b, c, d, GET(1), 0xf61e2562, 5)
        STEP(G, d, a, b, c, GET(6), 0xc040b340, 9)
        STEP(G, c, d, a, b, GET(11), 0x265e5a51, 14)
        STEP(G, b, c, d, a, GET(0), 0xe9b6c7aa, 20)
        STEP(G, a, b, c, d, GET(5), 0xd62f105d, 5)
        STEP(G, d, a, b, c, GET(10), 0x02441453, 9)
        STEP(G, c, d, a, b, GET(15), 0xd8a1e681, 14)
        STEP(G, b, c, d, a, GET(4), 0xe7d3fbc8, 20)
        STEP(G, a, b, c, d, GET(9), 0x21e1cde6, 5)
        STEP(G, d, a, b, c, GET(14), 0xc33707d6, 9)
        STEP(G, c, d, a, b, GET(3), 0xf4d50d87, 14)
        STEP(G, b, c, d, a, GET(8), 0x455a14ed, 20)
        STEP(G, a, b, c, d, GET(13), 0xa9e3e905, 5)
        STEP(G, d, a, b, c, GET(2), 0xfcefa3f8, 9)
        STEP(G, c, d, a, b, GET(7), 0x676f02d9, 14)
        STEP(G, b, c, d, a, GET(12), 0x8d2a4c8a, 20)

        /* Round 3 */
        STEP(H, a, b, c, d, GET(5), 0xfffa3942, 4)
        STEP(H2, d, a, b, c, GET(8), 0x8771f681, 11)
        STEP(H, c, d, a, b, GET(11), 0x6d9d6122, 16)
        STEP(H2, b, c, d, a, GET(14), 0xfde5380c, 23)
        STEP(H, a, b, c, d, GET(1), 0xa4beea44, 4)
        STEP(H2, d, a, b, c, GET(4), 0x4bdecfa9, 11)
        STEP(H, c, d, a, b, GET(7), 0xf6bb4b60, 16)
        STEP(H2, b, c, d, a, GET(10), 0xbebfbc70, 23)
        STEP(H, a, b, c, d, GET(13), 0x289b7ec6, 4)
        STEP(H2, d, a, b, c, GET(0), 0xeaa127fa, 11)
        STEP(H, c, d, a, b, GET(3), 0xd4ef3085, 16)
        STEP(H2, b, c, d, a, GET(6), 0x04881d05, 23)
        STEP(H, a, b, c, d, GET(9), 0xd9d4d039, 4)
        STEP(H2, d, a, b, c, GET(12), 0xe6db99e5, 11)
        STEP(H, c, d, a, b, GET(15), 0x1fa27cf8, 16)
        STEP(H2, b, c, d, a, GET(2), 0xc4ac5665, 23)

        /* Round 4 */
        STEP(I, a, b, c, d, GET(0), 0xf4292244, 6)
        STEP(I, d, a, b, c, GET(7), 0x432aff97, 10)
        STEP(I, c, d, a, b, GET(14), 0xab9423a7, 15)
        STEP(I, b, c, d, a, GET(5), 0xfc93a039, 21)
        STEP(I, a, b, c, d, GET(12), 0x655b59c3, 6)
        STEP(I, d, a, b, c, GET(3), 0x8f0ccc92, 10)
        STEP(I, c, d, a, b, GET(10), 0xffeff47d, 15)
        STEP(I, b, c, d, a, GET(1), 0x85845dd1, 21)
        STEP(I, a, b, c, d, GET(8), 0x6fa87e4f, 6)
        STEP(I, d, a, b, c, GET(15), 0xfe2ce6e0, 10)
        STEP(I, c, d, a, b, GET(6), 0xa3014314, 15)
        STEP(I, b, c, d, a, GET(13), 0x4e0811a1, 21)
        STEP(I, a, b, c, d, GET(4), 0xf7537e82, 6)
        STEP(I, d, a, b, c, GET(11), 0xbd3af235, 10)
        STEP(I, c, d, a, b, GET(2), 0x2ad7d2bb, 15)
        STEP(I, b, c, d, a, GET(9), 0xeb86d391, 21)

        a += saved_a;
        b += saved_b;
        c += saved_c;
        d += saved_d;

        ptr += 64;
    } while (size -= 64);

    ctx->a = a;
    ctx->b = b;
    ctx->c = c;
    ctx->d = d;

    return ptr;
}

static void md5_init(struct md5_ctx *ctx)
{
    ctx->a = 0x67452301;
    ctx->b = 0xefcdab89;
    ctx->c = 0x98badcfe;
    ctx->d = 0x10325476;

    ctx->lo = 0;
    ctx->hi = 0;
}

static void md5_update(struct md5_ctx *ctx, const void *data, size_t len)
{
    uint32_t saved_lo;
    unsigned long used, available;

    saved_lo = ctx->lo;
    if ((ctx->lo = (saved_lo + len) & 0x1fffffff) < saved_lo)
        ctx->hi++;
    ctx->hi += len >> 29;

    used = saved_lo & 0x3f;

    if (used) {
        available = 64 - used;

        if (len < available) {
            memcpy(&ctx->buffer[used], data, len);
            return;
        }

        memcpy(&ctx->buffer[used], data, available);
        data = (const unsigned char *)data + available;
        len -= available;
        body(ctx, ctx->buffer, 64);
    }

    if (len >= 64) {
        data = body(ctx, data, len & ~((size_t) 0x3f));
        len &= 0x3f;
    }

    memcpy(ctx->buffer, data, len);
}

static void md5_final(struct md5_ctx *ctx, uint8_t digest[16])
{
    unsigned long used, available;

    used = ctx->lo & 0x3f;

    ctx->buffer[used++] = 0x80;

    available = 64 - used;

    if (available < 8) {
        memset(&ctx->buffer[used], 0, available);
        body(ctx, ctx->buffer, 64);
        used = 0;
        available = 64;
    }

    memset(&ctx->buffer[used], 0, available - 8);

    ctx->lo <<= 3;
    ctx->buffer[56] = ctx->lo;
    ctx->buffer[57] = ctx->lo >> 8;
    ctx->buffer[58] = ctx->lo >> 16;
    ctx->buffer[59] = ctx->lo >> 24;
    ctx->buffer[60] = ctx->hi;
    ctx->buffer[61] = ctx->hi >> 8;
    ctx->buffer[62] = ctx->hi >> 16;
    ctx->buffer[63] = ctx->hi >> 24;

    body(ctx, ctx->buffer, 64);

    digest[0] = ctx->a;
    digest[1] = ctx->a >> 8;
    digest[2] = ctx->a >> 16;
    digest[3] = ctx->a >> 24;
    digest[4] = ctx->b;
    digest[5] = ctx->b >> 8;
    digest[6] = ctx->b >> 16;
    digest[7] = ctx->b >> 24;
    digest[8] = ctx->c;
    digest[9] = ctx->c >> 8;
    digest[10] = ctx->c >> 16;
    digest[11] = ctx->c >> 24;
    digest[12] = ctx->d;
    digest[13] = ctx->d >> 8;
    digest[14] = ctx->d >> 16;
    digest[15] = ctx->d >> 24;

    memset(ctx, 0, sizeof(*ctx));
}

static int lua_md5_sum(lua_State *L)
{
    size_t len;
    const char *data = luaL_checklstring(L, 1, &len);
    struct md5_ctx ctx;
    uint8_t hash[16];

    md5_init(&ctx);
    md5_update(&ctx, data, len);
    md5_final(&ctx, hash);

    lua_pushlstring(L, (const char *)hash, sizeof(hash));

    return 1;
}

static int lua_md5_update(lua_State *L)
{
    struct md5_ctx *ctx = luaL_checkudata(L, 1, MD5_MT);
    size_t len;
    const char *data = luaL_checklstring(L, 2, &len);

    md5_update(ctx, data, len);

    return 0;
}

static int lua_md5_final(lua_State *L)
{
    struct md5_ctx *ctx = luaL_checkudata(L, 1, MD5_MT);
    uint8_t hash[16];

    md5_final(ctx, hash);
    lua_pushlstring(L, (const char *)hash, sizeof(hash));

    return 1;
}

static const struct luaL_Reg md5_methods[] = {
    {"update", lua_md5_update},
    {"final", lua_md5_final},
    {NULL, NULL}
};

static int lua_md5_new(lua_State *L)
{
    struct md5_ctx *ctx = lua_newuserdata(L, sizeof(struct md5_ctx));

    lua_pushvalue(L, lua_upvalueindex(1));
    lua_setmetatable(L, -2);

    md5_init(ctx);

    return 1;
}

int luaopen_eco_hash_md5(lua_State *L)
{
    lua_newtable(L);

    lua_pushstring(L, MD5_MT);
    lua_setfield(L, -2, "mtname");

    lua_pushcfunction(L, lua_md5_sum);
    lua_setfield(L, -2, "sum");

    eco_new_metatable(L, MD5_MT, NULL, md5_methods);
    lua_pushcclosure(L, lua_md5_new, 1);
    lua_setfield(L, -2, "new");

    return 1;
}
