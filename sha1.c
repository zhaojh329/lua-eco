#include <arpa/inet.h>
#include <stdbool.h>
#include <stdint.h>

#include "eco.h"

#define ECO_SHA1_MT "eco{sha1}"

struct sha1_ctx {
    uint32_t state[5];
    size_t count[2];
    uint8_t buffer[64];
};

union char64long16 {
    uint8_t c[64];
    uint32_t l[16];
};

#define rol(value, bits) (((value) << (bits)) | ((value) >> (32 - (bits))))

static uint32_t blk0(union char64long16 *block, int i)
{
    /* Forrest: SHA expect big endian */
    block->l[i] = htonl(block->l[i]);
    return block->l[i];
}

#define blk(i)                                                               \
  (block->l[i & 15] = rol(block->l[(i + 13) & 15] ^ block->l[(i + 8) & 15] ^ \
                              block->l[(i + 2) & 15] ^ block->l[i & 15], 1))

#define R0(v, w, x, y, z, i)                                          \
  z += ((w & (x ^ y)) ^ y) + blk0(block, i) + 0x5A827999 + rol(v, 5); \
  w = rol(w, 30);
#define R1(v, w, x, y, z, i)                                  \
  z += ((w & (x ^ y)) ^ y) + blk(i) + 0x5A827999 + rol(v, 5); \
  w = rol(w, 30);
#define R2(v, w, x, y, z, i)                          \
  z += (w ^ x ^ y) + blk(i) + 0x6ED9EBA1 + rol(v, 5); \
  w = rol(w, 30);
#define R3(v, w, x, y, z, i)                                        \
  z += (((w | x) & y) | (w & x)) + blk(i) + 0x8F1BBCDC + rol(v, 5); \
  w = rol(w, 30);
#define R4(v, w, x, y, z, i)                          \
  z += (w ^ x ^ y) + blk(i) + 0xCA62C1D6 + rol(v, 5); \
  w = rol(w, 30);

static void sha1_transform(uint32_t state[5], const uint8_t buffer[64])
{
    uint32_t a, b, c, d, e;
    union char64long16 block[1];

    memcpy(block, buffer, 64);
    a = state[0];
    b = state[1];
    c = state[2];
    d = state[3];
    e = state[4];
    R0(a, b, c, d, e, 0);
    R0(e, a, b, c, d, 1);
    R0(d, e, a, b, c, 2);
    R0(c, d, e, a, b, 3);
    R0(b, c, d, e, a, 4);
    R0(a, b, c, d, e, 5);
    R0(e, a, b, c, d, 6);
    R0(d, e, a, b, c, 7);
    R0(c, d, e, a, b, 8);
    R0(b, c, d, e, a, 9);
    R0(a, b, c, d, e, 10);
    R0(e, a, b, c, d, 11);
    R0(d, e, a, b, c, 12);
    R0(c, d, e, a, b, 13);
    R0(b, c, d, e, a, 14);
    R0(a, b, c, d, e, 15);
    R1(e, a, b, c, d, 16);
    R1(d, e, a, b, c, 17);
    R1(c, d, e, a, b, 18);
    R1(b, c, d, e, a, 19);
    R2(a, b, c, d, e, 20);
    R2(e, a, b, c, d, 21);
    R2(d, e, a, b, c, 22);
    R2(c, d, e, a, b, 23);
    R2(b, c, d, e, a, 24);
    R2(a, b, c, d, e, 25);
    R2(e, a, b, c, d, 26);
    R2(d, e, a, b, c, 27);
    R2(c, d, e, a, b, 28);
    R2(b, c, d, e, a, 29);
    R2(a, b, c, d, e, 30);
    R2(e, a, b, c, d, 31);
    R2(d, e, a, b, c, 32);
    R2(c, d, e, a, b, 33);
    R2(b, c, d, e, a, 34);
    R2(a, b, c, d, e, 35);
    R2(e, a, b, c, d, 36);
    R2(d, e, a, b, c, 37);
    R2(c, d, e, a, b, 38);
    R2(b, c, d, e, a, 39);
    R3(a, b, c, d, e, 40);
    R3(e, a, b, c, d, 41);
    R3(d, e, a, b, c, 42);
    R3(c, d, e, a, b, 43);
    R3(b, c, d, e, a, 44);
    R3(a, b, c, d, e, 45);
    R3(e, a, b, c, d, 46);
    R3(d, e, a, b, c, 47);
    R3(c, d, e, a, b, 48);
    R3(b, c, d, e, a, 49);
    R3(a, b, c, d, e, 50);
    R3(e, a, b, c, d, 51);
    R3(d, e, a, b, c, 52);
    R3(c, d, e, a, b, 53);
    R3(b, c, d, e, a, 54);
    R3(a, b, c, d, e, 55);
    R3(e, a, b, c, d, 56);
    R3(d, e, a, b, c, 57);
    R3(c, d, e, a, b, 58);
    R3(b, c, d, e, a, 59);
    R4(a, b, c, d, e, 60);
    R4(e, a, b, c, d, 61);
    R4(d, e, a, b, c, 62);
    R4(c, d, e, a, b, 63);
    R4(b, c, d, e, a, 64);
    R4(a, b, c, d, e, 65);
    R4(e, a, b, c, d, 66);
    R4(d, e, a, b, c, 67);
    R4(c, d, e, a, b, 68);
    R4(b, c, d, e, a, 69);
    R4(a, b, c, d, e, 70);
    R4(e, a, b, c, d, 71);
    R4(d, e, a, b, c, 72);
    R4(c, d, e, a, b, 73);
    R4(b, c, d, e, a, 74);
    R4(a, b, c, d, e, 75);
    R4(e, a, b, c, d, 76);
    R4(d, e, a, b, c, 77);
    R4(c, d, e, a, b, 78);
    R4(b, c, d, e, a, 79);
    state[0] += a;
    state[1] += b;
    state[2] += c;
    state[3] += d;
    state[4] += e;
    /* Erase working structures. The order of operations is important,
    * used to ensure that compiler doesn't optimize those out. */
    memset(block, 0, sizeof(block));
    a = b = c = d = e = 0;
}

static void sha1_init(struct sha1_ctx *ctx)
{
    ctx->state[0] = 0x67452301;
    ctx->state[1] = 0xEFCDAB89;
    ctx->state[2] = 0x98BADCFE;
    ctx->state[3] = 0x10325476;
    ctx->state[4] = 0xC3D2E1F0;
    ctx->count[0] = ctx->count[1] = 0;
}

static void sha1_update(struct sha1_ctx *ctx, const void *data, size_t len)
{
    size_t i, j;

    j = ctx->count[0];
    ctx->count[0] += len << 3;

    if (ctx->count[0] < j)
        ctx->count[1]++;

    ctx->count[1] += (len >> 29);
    j = (j >> 3) & 63;

    if ((j + len) > 63) {
        i = 64 - j;
        memcpy(ctx->buffer + j, data, i);
        sha1_transform(ctx->state, ctx->buffer);
        for (; i + 63 < len; i += 64)
            sha1_transform(ctx->state, data + i);
        j = 0;
    } else {
        i = 0;
    }

    memcpy(ctx->buffer + j, data + i, len - i);
}

static void sha1_final(struct sha1_ctx *ctx, uint8_t digest[20])
{
    unsigned i;
    uint8_t finalcount[8], c;

    for (i = 0; i < 8; i++)
        finalcount[i] = (ctx->count[(i >= 4 ? 0 : 1)] >> ((3 - (i & 3)) * 8)) & 255;

    c = 0200;
    sha1_update(ctx, &c, 1);

    while ((ctx->count[0] & 504) != 448) {
        c = 0000;
        sha1_update(ctx, &c, 1);
    }

    sha1_update(ctx, finalcount, 8);

    for (i = 0; i < 20; i++)
        digest[i] = (ctx->state[i >> 2] >> ((3 - (i & 3)) * 8)) & 255;
}

static int lua_sha1_sum(lua_State *L)
{
    size_t len;
    const char *data = luaL_checklstring(L, 1, &len);
    struct sha1_ctx ctx;
    uint8_t hash[20];

    sha1_init(&ctx);
    sha1_update(&ctx, data, len);
    sha1_final(&ctx, hash);

    lua_pushlstring(L, (const char *)hash, 20);

    return 1;
}

static int lua_sha1_update(lua_State *L)
{
    struct sha1_ctx *ctx = luaL_checkudata(L, 1, ECO_SHA1_MT);
    size_t len;
    const char *data = luaL_checklstring(L, 2, &len);

    sha1_update(ctx, data, len);

    return 0;
}

static int lua_sha1_final(lua_State *L)
{
    struct sha1_ctx *ctx = luaL_checkudata(L, 1, ECO_SHA1_MT);
    uint8_t hash[20];

    sha1_final(ctx, hash);
    lua_pushlstring(L, (const char *)hash, 20);

    return 1;
}

static const struct luaL_Reg sha1_methods[] = {
    {"update", lua_sha1_update},
    {"final", lua_sha1_final},
    {NULL, NULL}
};

static int lua_sha1_new(lua_State *L)
{
    struct sha1_ctx *ctx = lua_newuserdata(L, sizeof(struct sha1_ctx));

    lua_pushvalue(L, lua_upvalueindex(1));
    lua_setmetatable(L, -2);

    sha1_init(ctx);

    return 1;
}

int luaopen_eco_crypto_sha1(lua_State *L)
{
    lua_newtable(L);

    lua_pushcfunction(L, lua_sha1_sum);
    lua_setfield(L, -2, "sum");

    eco_new_metatable(L, ECO_SHA1_MT, sha1_methods);
    lua_pushcclosure(L, lua_sha1_new, 1);
    lua_setfield(L, -2, "new");

    return 1;
}
