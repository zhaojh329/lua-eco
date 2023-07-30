/* SPDX-License-Identifier: MIT */
/*
 * Author: Jianhui Zhao <zhaojh329@gmail.com>
 */

#include <endian.h>

#include "eco.h"

static bool read_num(lua_State *L, void *dest, int n)
{
    size_t len;
    const uint8_t *data = (const uint8_t *)luaL_checklstring(L, 1, &len);
    lua_Number offset = luaL_optnumber(L, 2, 0);

    if (len - offset  < n)
        return false;

    memcpy(dest, data + (size_t)offset, n);

    return true;
}

static int eco_binary_read_u8(lua_State *L)
{
    uint8_t val = 0;
    bool ok;

    ok = read_num(L, &val, 1);

    lua_pushinteger(L, val);
    lua_pushboolean(L, ok);

    return 2;
}

static int eco_binary_read_u16(lua_State *L)
{
    uint16_t val = 0;
    bool ok;

    ok = read_num(L, &val, 2);

    lua_pushinteger(L, val);
    lua_pushboolean(L, ok);

    return 2;
}

static int eco_binary_read_u32(lua_State *L)
{
    uint32_t val = 0;
    bool ok;

    ok = read_num(L, &val, 4);

    lua_pushint(L, val);
    lua_pushboolean(L, ok);

    return 2;
}

static int eco_binary_read_u64(lua_State *L)
{
    uint64_t val = 0;
    bool ok;

    ok = read_num(L, &val, 8);

    lua_pushint(L, val);
    lua_pushboolean(L, ok);

    return 2;
}

static int eco_binary_read_u16le(lua_State *L)
{
    uint16_t val = 0;
    bool ok;

    ok = read_num(L, &val, 2);

    lua_pushinteger(L, le16toh(val));
    lua_pushboolean(L, ok);

    return 2;
}

static int eco_binary_read_u32le(lua_State *L)
{
    uint32_t val = 0;
    bool ok;

    ok = read_num(L, &val, 4);

    lua_pushint(L, le32toh(val));
    lua_pushboolean(L, ok);

    return 2;
}

static int eco_binary_read_u64le(lua_State *L)
{
    uint64_t val = 0;
    bool ok;

    ok = read_num(L, &val, 8);

    lua_pushint(L, le64toh(val));
    lua_pushboolean(L, ok);

    return 2;
}

static int eco_binary_read_u16be(lua_State *L)
{
    uint16_t val = 0;
    bool ok;

    ok = read_num(L, &val, 2);

    lua_pushinteger(L, be16toh(val));
    lua_pushboolean(L, ok);

    return 2;
}

static int eco_binary_read_u32be(lua_State *L)
{
    uint32_t val = 0;
    bool ok;

    ok = read_num(L, &val, 4);

    lua_pushint(L, be32toh(val));
    lua_pushboolean(L, ok);

    return 2;
}

static int eco_binary_read_u64be(lua_State *L)
{
    uint64_t val = 0;
    bool ok;

    ok = read_num(L, &val, 8);

    lua_pushint(L, be64toh(val));
    lua_pushboolean(L, ok);

    return 2;
}

int luaopen_eco_binary(lua_State *L)
{
    lua_newtable(L);

    lua_pushcfunction(L, eco_binary_read_u8);
    lua_setfield(L, -2, "read_u8");

    lua_pushcfunction(L, eco_binary_read_u16);
    lua_setfield(L, -2, "read_u16");

    lua_pushcfunction(L, eco_binary_read_u32);
    lua_setfield(L, -2, "read_u32");

    lua_pushcfunction(L, eco_binary_read_u64);
    lua_setfield(L, -2, "read_u64");

    lua_pushcfunction(L, eco_binary_read_u16le);
    lua_setfield(L, -2, "read_u16le");

    lua_pushcfunction(L, eco_binary_read_u32le);
    lua_setfield(L, -2, "read_u32le");

    lua_pushcfunction(L, eco_binary_read_u64le);
    lua_setfield(L, -2, "read_u64le");

    lua_pushcfunction(L, eco_binary_read_u16be);
    lua_setfield(L, -2, "read_u16be");

    lua_pushcfunction(L, eco_binary_read_u32be);
    lua_setfield(L, -2, "read_u32be");

    lua_pushcfunction(L, eco_binary_read_u64be);
    lua_setfield(L, -2, "read_u64be");

    return 1;
}
