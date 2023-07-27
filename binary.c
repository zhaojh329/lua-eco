/* SPDX-License-Identifier: MIT */
/*
 * Author: Jianhui Zhao <zhaojh329@gmail.com>
 */

#include <endian.h>

#include "eco.h"

static bool read_num(const uint8_t *data, size_t len, size_t offset, void *dest, int n)
{
    if (len - offset  < n)
        return false;

    memcpy(dest, data + offset, n);

    return true;
}

static int eco_binary_read_u8(lua_State *L)
{
    size_t len;
    const uint8_t *data = (const uint8_t *)luaL_checklstring(L, 1, &len);
    size_t offset = luaL_optinteger(L, 2, 0);
    uint8_t val = 0;
    bool ok;

    ok = read_num(data, len, offset, &val, 1);

    lua_pushinteger(L, val);
    lua_pushboolean(L, ok);

    return 2;
}

static int eco_binary_read_u16(lua_State *L)
{
    size_t len;
    const uint8_t *data = (const uint8_t *)luaL_checklstring(L, 1, &len);
    size_t offset = luaL_optinteger(L, 2, 0);
    uint16_t val = 0;
    bool ok;

    ok = read_num(data, len, offset, &val, 2);

    lua_pushinteger(L, val);
    lua_pushboolean(L, ok);

    return 2;
}

static int eco_binary_read_u32(lua_State *L)
{
    size_t len;
    const uint8_t *data = (const uint8_t *)luaL_checklstring(L, 1, &len);
    size_t offset = luaL_optinteger(L, 2, 0);
    uint32_t val = 0;
    bool ok;

    ok = read_num(data, len, offset, &val, 4);

    lua_pushint(L, val);
    lua_pushboolean(L, ok);

    return 2;
}

static int eco_binary_read_u64(lua_State *L)
{
    size_t len;
    const uint8_t *data = (const uint8_t *)luaL_checklstring(L, 1, &len);
    size_t offset = luaL_optinteger(L, 2, 0);
    uint64_t val = 0;
    bool ok;

    ok = read_num(data, len, offset, &val, 8);

    lua_pushint(L, val);
    lua_pushboolean(L, ok);

    return 2;
}

static int eco_binary_read_u16le(lua_State *L)
{
    size_t len;
    const uint8_t *data = (const uint8_t *)luaL_checklstring(L, 1, &len);
    size_t offset = luaL_optinteger(L, 2, 0);
    uint16_t val = 0;
    bool ok;

    ok = read_num(data, len, offset, &val, 2);

    lua_pushinteger(L, le16toh(val));
    lua_pushboolean(L, ok);

    return 2;
}

static int eco_binary_read_u32le(lua_State *L)
{
    size_t len;
    const uint8_t *data = (const uint8_t *)luaL_checklstring(L, 1, &len);
    size_t offset = luaL_optinteger(L, 2, 0);
    uint32_t val = 0;
    bool ok;

    ok = read_num(data, len, offset, &val, 4);

    lua_pushint(L, le32toh(val));
    lua_pushboolean(L, ok);

    return 2;
}

static int eco_binary_read_u64le(lua_State *L)
{
    size_t len;
    const uint8_t *data = (const uint8_t *)luaL_checklstring(L, 1, &len);
    size_t offset = luaL_optinteger(L, 2, 0);
    uint64_t val = 0;
    bool ok;

    ok = read_num(data, len, offset, &val, 8);

    lua_pushint(L, le64toh(val));
    lua_pushboolean(L, ok);

    return 2;
}

static int eco_binary_read_u16be(lua_State *L)
{
    size_t len;
    const uint8_t *data = (const uint8_t *)luaL_checklstring(L, 1, &len);
    size_t offset = luaL_optinteger(L, 2, 0);
    uint16_t val = 0;
    bool ok;

    ok = read_num(data, len, offset, &val, 2);

    lua_pushinteger(L, be16toh(val));
    lua_pushboolean(L, ok);

    return 2;
}

static int eco_binary_read_u32be(lua_State *L)
{
    size_t len;
    const uint8_t *data = (const uint8_t *)luaL_checklstring(L, 1, &len);
    size_t offset = luaL_optinteger(L, 2, 0);
    uint32_t val = 0;
    bool ok;

    ok = read_num(data, len, offset, &val, 4);

    lua_pushint(L, be32toh(val));
    lua_pushboolean(L, ok);

    return 2;
}

static int eco_binary_read_u64be(lua_State *L)
{
    size_t len;
    const uint8_t *data = (const uint8_t *)luaL_checklstring(L, 1, &len);
    size_t offset = luaL_optinteger(L, 2, 0);
    uint64_t val = 0;
    bool ok;

    ok = read_num(data, len, offset, &val, 8);

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
