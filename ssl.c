/* SPDX-License-Identifier: MIT */
/*
 * Author: Jianhui Zhao <zhaojh329@gmail.com>
 */

#include <string.h>
#include <unistd.h>
#include <stdlib.h>
#include <errno.h>
#include <glob.h>

#include "ssl/ssl.h"
#include "eco.h"

struct eco_ssl_context {
    struct ssl_context *ctx;
    bool is_server;
};

struct eco_ssl_session {
    struct eco_ssl_context *ctx;
    struct ssl *ssl;
    bool insecure;
    uint8_t flags;
};

#define ECO_SSL_CTX_MT  "struct eco_ssl_context *"
#define ECO_SSL_MT  "struct eco_ssl_session *"

static int eco_ssl_context_free(lua_State *L)
{
    struct eco_ssl_context *ctx = luaL_checkudata(L, 1, ECO_SSL_CTX_MT);

    if (!ctx->ctx)
        return 0;

    ssl_context_free(ctx->ctx);
    ctx->ctx = NULL;

    return 0;
}

static int eco_ssl_context_gc(lua_State *L)
{
    return eco_ssl_context_free(L);
}

static int lua_ssl_free(lua_State *L)
{
    struct eco_ssl_session *s = luaL_checkudata(L, 1, ECO_SSL_MT);

    if (!s->ssl)
        return 0;

    ssl_session_free(s->ssl);
    s->ssl = NULL;

    return 0;
}

static int lua_ssl_pointer(lua_State *L)
{
    struct eco_ssl_session *s = luaL_checkudata(L, 1, ECO_SSL_MT);

    lua_pushlightuserdata(L, s);
    return 1;
}

static int lua_ssl_set_server_name(lua_State *L)
{
    struct eco_ssl_session *s = luaL_checkudata(L, 1, ECO_SSL_MT);
    const char *name = luaL_checkstring(L, 2);

    ssl_set_server_name(s->ssl, name);

    return 0;
}

static void on_ssl_verify_error(int error, const char *str, void *arg)
{
    *(const char **)arg = str;
}

static int lua_ssl_handshake(lua_State *L)
{
    struct eco_ssl_session *s = luaL_checkudata(L, 1, ECO_SSL_MT);
    const char *verify_error = NULL;
    char err_buf[128];
    int ret;

    if (s->ctx->is_server)
        ret = ssl_accept(s->ssl, on_ssl_verify_error, &verify_error);
    else
        ret = ssl_connect(s->ssl, on_ssl_verify_error, &verify_error);

    if (ret < 0) {
        if (ret == SSL_ERROR) {
            lua_pushnil(L);
            lua_pushstring(L, ssl_last_error_string(s->ssl, err_buf, sizeof(err_buf)));
            return 2;
        }

        lua_pushinteger(L, ret);
        return 1;
    }

    if (verify_error && !s->insecure) {
        lua_pushnil(L);
        lua_pushfstring(L, "SSL certificate verify fail: %s", verify_error);
        return 2;
    }

    lua_pushboolean(L, true);
    return 1;
}

static int lua_ssl_session_new(lua_State *L)
{
    struct eco_ssl_context *ctx = luaL_checkudata(L, 1, ECO_SSL_CTX_MT);
    int fd = luaL_checkinteger(L, 2);
    bool insecure = lua_toboolean(L, 3);
    struct eco_ssl_session *s;

    s = lua_newuserdata(L, sizeof(struct eco_ssl_session));
    memset(s, 0, sizeof(struct eco_ssl_session));
    luaL_setmetatable(L, ECO_SSL_MT);

    s->ssl = ssl_session_new(ctx->ctx, fd);
    s->insecure = insecure;
    s->ctx = ctx;

    return 1;
}

static int eco_ssl_load_ca_cert_file(lua_State *L)
{
    struct eco_ssl_context *ctx = luaL_checkudata(L, 1, ECO_SSL_CTX_MT);
    const char *file = luaL_checkstring(L, 2);

    lua_pushboolean(L, !!!ssl_load_ca_cert_file(ctx->ctx, file));
    return 1;
}

static int eco_ssl_load_cert_file(lua_State *L)
{
    struct eco_ssl_context *ctx = luaL_checkudata(L, 1, ECO_SSL_CTX_MT);
    const char *file = luaL_checkstring(L, 2);

    lua_pushboolean(L, !!!ssl_load_cert_file(ctx->ctx, file));
    return 1;
}

static int eco_ssl_load_key_file(lua_State *L)
{
    struct eco_ssl_context *ctx = luaL_checkudata(L, 1, ECO_SSL_CTX_MT);
    const char *file = luaL_checkstring(L, 2);

    lua_pushboolean(L, !!!ssl_load_key_file(ctx->ctx, file));
    return 1;
}

static int eco_ssl_set_ciphers(lua_State *L)
{
    struct eco_ssl_context *ctx = luaL_checkudata(L, 1, ECO_SSL_CTX_MT);
    const char *ciphers = luaL_checkstring(L, 2);

    lua_pushboolean(L, !!!ssl_set_ciphers(ctx->ctx, ciphers));
    return 1;
}

static int eco_ssl_set_require_validation(lua_State *L)
{
    struct eco_ssl_context *ctx = luaL_checkudata(L, 1, ECO_SSL_CTX_MT);
    bool require = lua_toboolean(L, 2);

    ssl_set_require_validation(ctx->ctx, require);
    return 0;
}

static void load_default_ca_cert(struct ssl_context *ctx)
{
	glob_t gl;
	size_t i;

	glob("/etc/ssl/certs/*.crt", 0, NULL, &gl);

	for (i = 0; i < gl.gl_pathc; i++)
		ssl_load_ca_cert_file(ctx, gl.gl_pathv[i]);

	globfree(&gl);
}

static int lua_ssl_context_new(lua_State *L)
{
    bool is_server = lua_toboolean(L, 1);
    struct eco_ssl_context *ctx;

    ctx = lua_newuserdata(L, sizeof(struct eco_ssl_context));
    memset(ctx, 0, sizeof(struct eco_ssl_context));
    luaL_setmetatable(L, ECO_SSL_CTX_MT);

    ctx->ctx = ssl_context_new(is_server);
    ctx->is_server = is_server;

    load_default_ca_cert(ctx->ctx);

    return 1;
}

static const struct luaL_Reg ssl_ctx_methods[] =  {
    {"new", lua_ssl_session_new},
    {"free", eco_ssl_context_free},
    {"load_ca_cert_file", eco_ssl_load_ca_cert_file},
    {"load_cert_file", eco_ssl_load_cert_file},
    {"load_key_file", eco_ssl_load_key_file},
    {"set_ciphers", eco_ssl_set_ciphers},
    {"require_validation", eco_ssl_set_require_validation},
    {NULL, NULL}
};

static const struct luaL_Reg ssl_ctx_mt[] =  {
    {"__gc", eco_ssl_context_gc},
    {"__close", eco_ssl_context_gc},
    {NULL, NULL}
};

static const struct luaL_Reg ssl_methods[] =  {
    {"free", lua_ssl_free},
    {"pointer", lua_ssl_pointer},
    {"set_server_name", lua_ssl_set_server_name},
    {"handshake", lua_ssl_handshake},
    {NULL, NULL}
};

static const struct luaL_Reg ssl_mt[] =  {
    {"__gc", lua_ssl_free},
    {"__close", lua_ssl_free},
    {NULL, NULL}
};

static int lua_ssl_read(void *buf, size_t len, void *ctx, const char **err)
{
    struct eco_ssl_session *s = ctx;
    static char err_buf[128];
    ssize_t ret;

    ret = ssl_read(s->ssl, buf, len);
    if (unlikely(ret < 0)) {
        if (ret == SSL_ERROR) {
            *err = ssl_last_error_string(s->ssl, err_buf, sizeof(err_buf));
            return -1;
        }

        return -EAGAIN;
    }

    return ret;
}

static int lua_ssl_write(const void *buf, size_t len, void *ctx, const char **err)
{
    struct eco_ssl_session *s = ctx;
    static char err_buf[128];
    ssize_t ret;

    ret = ssl_write(s->ssl, buf, len);
    if (unlikely(ret < 0)) {
        if (ret == SSL_ERROR) {
            *err = ssl_last_error_string(s->ssl, err_buf, sizeof(err_buf));
            return -1;
        }
        return -EAGAIN;
    }

    return ret;
}

int luaopen_eco_internal_ssl(lua_State *L)
{
    creat_metatable(L, ECO_SSL_CTX_MT, ssl_ctx_mt, ssl_ctx_methods);
    creat_metatable(L, ECO_SSL_MT, ssl_mt, ssl_methods);

    lua_newtable(L);

    lua_add_constant(L, "OK", SSL_OK);
    lua_add_constant(L, "ERROR", SSL_ERROR);
    lua_add_constant(L, "WANT_READ", SSL_WANT_READ);
    lua_add_constant(L, "WANT_WRITE", SSL_WANT_WRITE);
    lua_add_constant(L, "INSECURE", SSL_INSECURE);

    lua_pushcfunction(L, lua_ssl_context_new);
    lua_setfield(L, -2, "context");

    lua_pushlightuserdata(L, lua_ssl_read);
    lua_setfield(L, -2, "read");

    lua_pushlightuserdata(L, lua_ssl_write);
    lua_setfield(L, -2, "write");

    return 1;
}
