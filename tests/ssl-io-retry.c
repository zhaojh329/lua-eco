/* SPDX-License-Identifier: MIT */
/* Deterministic backend retries through the production ssl.c adapters.
 * Build from the repository root (OpenSSL build):
 * cc -shared -fPIC -Wall -Werror -I. $(pkg-config --cflags lua5.4) \
 *   ssl.c tests/ssl-io-retry.c build/ssl/libxssl.a \
 *   -Wl,--wrap=ssl_read -Wl,--wrap=ssl_write \
 *   $(pkg-config --libs lua5.4 openssl) -o build/ssl_io_retry.so
 */

#include "eco.h"
#include "ssl/ssl.h"

static int retry_result;
static int retries;
static int calls;

int luaopen_eco_internal_ssl(lua_State *L);

static int configure(lua_State *L)
{
    retry_result = luaL_checkinteger(L, 1);
    retries = luaL_checkinteger(L, 2);
    calls = 0;
    return 0;
}

static int call_count(lua_State *L)
{
    lua_pushinteger(L, calls);
    return 1;
}

int __wrap_ssl_read(struct ssl *ssl, void *buf, int len)
{
    calls++;

    if (calls <= retries)
        return retry_result;

    if (len > 0) {
        memcpy(buf, "x", 1);
        return 1;
    }

    return 0;
}

int __wrap_ssl_write(struct ssl *ssl, const void *buf, int len)
{
    calls++;

    if (calls <= retries)
        return retry_result;

    return len;
}

int luaopen_ssl_io_retry(lua_State *L)
{
    luaopen_eco_internal_ssl(L);

    lua_pushcfunction(L, configure);
    lua_setfield(L, -2, "configure");
    lua_pushcfunction(L, call_count);
    lua_setfield(L, -2, "call_count");
    return 1;
}
