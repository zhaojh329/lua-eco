/* SPDX-License-Identifier: MIT */
/*
 * Author: Jianhui Zhao <zhaojh329@gmail.com>
 */

#include <sys/types.h>
#include <ctype.h>

#include "eco.h"

#define ALIGN(len, to)		(((len) + to - 1) & ~(to - 1))

#define MIN(X, Y) ((X) < (Y) ? (X) : (Y))

static size_t max_buf_size = 4096;

static void pack_single(lua_State *L, char *buf, void *val, size_t type_size,
        size_t *len, size_t *max_align)
{
    size_t align_size = MIN(sizeof(long), type_size);

    if (align_size > *max_align)
        *max_align = align_size;

    *len = ALIGN(*len, align_size);

    if (*len + type_size > max_buf_size)
        luaL_error(L, "buf is full");

    memcpy(buf + *len, val, type_size);

    *len += type_size;
}

static void pack_single_fixed_signed(lua_State *L, int size, int arg,
        char *buf, size_t *len, size_t *max_align)
{
    if (size != 8 && size != 16 && size != 32 && size != 64)
        luaL_argerror(L, 1, "invalid format");
    
    switch (size) {
    case 8: {
        int8_t val = (int8_t)luaL_checkinteger(L, arg);
        pack_single(L, buf, &val, sizeof(val), len, max_align);
        break;
    }

    case 16: {
        int16_t val = (int16_t)luaL_checkinteger(L, arg);
        pack_single(L, buf, &val, sizeof(val), len, max_align);
        break;
    }

    case 32: {
        int32_t val = (int32_t)luaL_checkinteger(L, arg);
        pack_single(L, buf, &val, sizeof(val), len, max_align);
        break;
    }

    case 64: {
        int64_t val;

        if (sizeof(lua_Integer) < 8)
            val = (int64_t)luaL_checknumber(L, arg);
        else
            val = (int64_t)luaL_checkinteger(L, arg);

        pack_single(L, buf, &val, sizeof(val), len, max_align);
        break;
    }
    }
}

static void pack_single_fixed_unsigned(lua_State *L, int size, int arg,
        char *buf, size_t *len, size_t *max_align)
{
        if (size != 8 && size != 16 && size != 32 && size != 64)
        luaL_argerror(L, 1, "invalid format");
    
    switch (size) {
    case 8: {
        uint8_t val = (uint8_t)luaL_checkinteger(L, arg);
        pack_single(L, buf, &val, sizeof(val), len, max_align);
        break;
    }

    case 16: {
        uint16_t val = (uint16_t)luaL_checkinteger(L, arg);
        pack_single(L, buf, &val, sizeof(val), len, max_align);
        break;
    }

    case 32: {
        uint32_t val;

        if (sizeof(lua_Integer) < 8)
            val = (uint32_t)luaL_checknumber(L, arg);
        else
            val = (uint32_t)luaL_checkinteger(L, arg);

        pack_single(L, buf, &val, sizeof(val), len, max_align);
        break;
    }

    case 64: {
        uint64_t val;

        if (sizeof(lua_Integer) < 8)
            val = (uint64_t)luaL_checknumber(L, arg);
        else
            val = (uint64_t)luaL_checkinteger(L, arg);

        pack_single(L, buf, &val, sizeof(val), len, max_align);
        break;
    }
    }
}

/*
 * c: char
 * s: signed
 * u: unsigned
 * u8: uint8_t
 * u16: uint16_t
 * u32: uint32_t
 * u64: uint64_t
 * h: short
 * H: unsigned short
 * i: int
 * i8: int8_t
 * i16: int16_t
 * i32: int32_t
 * i64: int64_t
 * I: unsigned int
 * l: long
 * L: unsigned long
 * q: long long
 * Q: unsigned long long
 * n: ssize_t
 * N: size_t
 * f: float
 * d: double
 * S: char[]
 */
static int eco_struct_pack(lua_State *L)
{
    const char *fmt = luaL_checkstring(L, 1);
    char buf[max_buf_size];
    size_t max_align = 0;
    size_t len = 0;
    int i, arg = 2;

    memset(buf, 0, max_buf_size);

    for (i = 0; i < strlen(fmt); i++) {
        switch (fmt[i]) {
        case 'c': {
            char val = *luaL_checkstring(L, arg++);
            pack_single(L, buf, &val, sizeof(val), &len, &max_align);
            break;
        }

        case 's': {
            signed val;

            if (sizeof(lua_Integer) < 8)
                val = (signed)luaL_checknumber(L, arg++);
            else
                val = (signed)luaL_checkinteger(L, arg++);

            pack_single(L, buf, &val, sizeof(val), &len, &max_align);
            break;
        }

        case 'u': {
            if (isdigit(fmt[i + 1])) {
                int size = fmt[i++ + 1] - '0';

                if (isdigit(fmt[i + 1]))
                    size = size * 10 + fmt[i++ + 1] - '0';

                pack_single_fixed_unsigned(L, size, arg++, buf, &len, &max_align);
            } else {
                unsigned val;

                if (sizeof(lua_Integer) < 8)
                    val = (unsigned)luaL_checknumber(L, arg++);
                else
                    val = (unsigned)luaL_checkinteger(L, arg++);

                pack_single(L, buf, &val, sizeof(val), &len, &max_align);
            }
            break;
        }

        case 'h': {
            short val = (short)luaL_checkinteger(L, arg++);
            pack_single(L, buf, &val, sizeof(val), &len, &max_align);
            break;
        }

        case 'H': {
            unsigned short val = (unsigned short)luaL_checkinteger(L, arg++);
            pack_single(L, buf, &val, sizeof(val), &len, &max_align);
            break;
        }

        case 'i': {
            if (isdigit(fmt[i + 1])) {
                int size = fmt[i++ + 1] - '0';

                if (isdigit(fmt[i + 1]))
                    size = size * 10 + fmt[i++ + 1] - '0';

                pack_single_fixed_signed(L, size, arg++, buf, &len, &max_align);
            } else {
                int val = (int)luaL_checkinteger(L, arg++);
                pack_single(L, buf, &val, sizeof(val), &len, &max_align);
            }
            break;
        }

        case 'I': {
            unsigned int val;

            if (sizeof(lua_Integer) < 8)
                val = (unsigned int)luaL_checknumber(L, arg++);
            else
                val = (unsigned int)luaL_checkinteger(L, arg++);

            pack_single(L, buf, &val, sizeof(val), &len, &max_align);
            break;
        }

        case 'l': {
            long val;

            if (sizeof(lua_Integer) < 8)
                val = (long)luaL_checknumber(L, arg++);
            else
                val = (long)luaL_checkinteger(L, arg++);

            pack_single(L, buf, &val, sizeof(val), &len, &max_align);
            break;
        }

        case 'L': {
            unsigned long val;

            if (sizeof(lua_Integer) < 8)
                val = (unsigned long)luaL_checknumber(L, arg++);
            else
                val = (unsigned long)luaL_checkinteger(L, arg++);

            pack_single(L, buf, &val, sizeof(val), &len, &max_align);

            break;
        }

        case 'q': {
            long long val;

                if (sizeof(lua_Integer) < 8)
                val = (long long)luaL_checknumber(L, arg++);
            else
                val = (long long)luaL_checkinteger(L, arg++);

            pack_single(L, buf, &val, sizeof(val), &len, &max_align);

            break;
        }

        case 'Q': {
            unsigned long long val;

            if (sizeof(lua_Integer) < 8)
                val = (unsigned long long)luaL_checknumber(L, arg++);
            else
                val = (unsigned long long)luaL_checkinteger(L, arg++);

            pack_single(L, buf, &val, sizeof(val), &len, &max_align);

            break;
        }

        case 'n': {
            ssize_t val;

            if (sizeof(lua_Integer) < 8)
                val = (ssize_t)luaL_checknumber(L, arg++);
            else
                val = (ssize_t)luaL_checkinteger(L, arg++);

            pack_single(L, buf, &val, sizeof(val), &len, &max_align);
            break;
        }

        case 'N': {
            size_t val;

            if (sizeof(lua_Integer) < 8)
                val = (size_t)luaL_checknumber(L, arg++);
            else
                val = (size_t)luaL_checkinteger(L, arg++);

            pack_single(L, buf, &val, sizeof(val), &len, &max_align);
            break;
        }

        case 'f': {
            float val = luaL_checknumber(L, arg++);
            pack_single(L, buf, &val, sizeof(val), &len, &max_align);
            break;
        }

        case 'd': {
            double val = luaL_checknumber(L, arg++);
            pack_single(L, buf, &val, sizeof(val), &len, &max_align);
            break;
        }

        case 'S': {
            size_t sl;
            const char *s = luaL_checklstring(L, arg++, &sl);

            if (sizeof(char) > max_align)
                max_align = sizeof(char);

            memcpy(buf + len, s, sl);
            len += sl;

            break;
        }

        default:
            luaL_argerror(L, 1, "invalid format");
        }
    }

    len = ALIGN(len, max_align);

    lua_pushlstring(L, buf, len);
    return 1;
}

int luaopen_eco_struct(lua_State *L)
{
    lua_newtable(L);

    lua_add_constant(L, "max_buf_size", max_buf_size);

    lua_pushcfunction(L, eco_struct_pack);
    lua_setfield(L, -2, "pack");

    return 1;
}
