/* SPDX-License-Identifier: MIT */
/*
 * Author: Jianhui Zhao <zhaojh329@gmail.com>
 */

#include <unistd.h>
#include <stdlib.h>
#include <errno.h>
#include <glob.h>

#include "ssl/ssl.h"
#include "bufio.h"
#include "eco.h"

struct eco_ssl_context {
    struct ssl_context *ctx;
    bool is_server;
};

struct eco_ssl_session {
    struct ssl_context *cxt;
    struct ssl *ssl;
    bool is_server;
    bool insecure;
    int state;
};

#define ECO_SSL_CTX_MT  "eco{ssl-ctx}"
#define ECO_SSL_MT  "eco{ssl}"

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

static int eco_ssl_free(lua_State *L)
{
    struct eco_ssl_session *s = luaL_checkudata(L, 1, ECO_SSL_MT);

    if (!s->ssl)
        return 0;

    ssl_session_free(s->ssl);
    s->ssl = NULL;

    return 0;
}

static int eco_ssl_gc(lua_State *L)
{
    return eco_ssl_free(L);
}

static int eco_ssl_set_server_name(lua_State *L)
{
    struct eco_ssl_session *s = luaL_checkudata(L, 1, ECO_SSL_MT);
    const char *name = luaL_checkstring(L, 2);

    ssl_set_server_name(s->ssl, name);

    return 0;
}

static void on_ssl_verify_error(int error, const char *str, void *arg)
{
    bool *valid_cert = arg;

    *valid_cert = false;
}

static int eco_ssl_ssl_negotiate(lua_State *L)
{
    struct eco_ssl_session *s = luaL_checkudata(L, 1, ECO_SSL_MT);
    bool valid_cert = true;
    char err_buf[128];
    int ret;

    if (s->is_server)
        ret = ssl_accept(s->ssl, on_ssl_verify_error, &valid_cert);
    else
        ret = ssl_connect(s->ssl, on_ssl_verify_error, &valid_cert);

    if (ret < 0) {
        s->state = ret;
        lua_pushboolean(L, false);
        if (ret == SSL_ERROR) {
            lua_pushstring(L, ssl_last_error_string(s->ssl, err_buf, sizeof(err_buf)));
            return 2;
        }
        return 1;
    }

    s->state = SSL_OK;

    if (!valid_cert && !s->insecure) {

        lua_pushboolean(L, false);
        lua_pushliteral(L, "SSL certificate verify fail");
        return 2;
    }

    lua_pushboolean(L, true);
    return 1;
}

static int eco_ssl_read(lua_State *L)
{
    struct eco_ssl_session *s = luaL_checkudata(L, 1, ECO_SSL_MT);
    size_t n = luaL_checkinteger(L, 2);
    static char err_buf[128];
    char *buf;
    int ret;

    if (n < 1)
        luaL_argerror(L, 2, "must be greater than 0");

    buf = malloc(n);
    if (!buf) {
        lua_pushnil(L);
        lua_pushstring(L, strerror(errno));
        return 2;
    }

    ret = ssl_read(s->ssl, buf, n);
    if (unlikely(ret < 0)) {
        s->state = ret;
        free(buf);
        lua_pushnil(L);
        if (ret == SSL_ERROR) {
            lua_pushstring(L, ssl_last_error_string(s->ssl, err_buf, sizeof(err_buf)));
            return 2;
        }
        return 1;
    }

    s->state = SSL_OK;

    lua_pushlstring(L, buf, ret);
    free(buf);

    return 1;
}

static int eco_ssl_read_to_buffer(lua_State *L)
{
    struct eco_ssl_session *s = luaL_checkudata(L, 1, ECO_SSL_MT);
    struct eco_bufio *b = luaL_checkudata(L, 2, ECO_BUFIO_MT);
    size_t n = buffer_room(b);
    static char err_buf[128];
    ssize_t ret;

    if (n == 0) {
        lua_pushnil(L);
        lua_pushliteral(L, "buffer is full");
        return 2;
    }

    ret = ssl_read(s->ssl, b->data + b->w, n);
    if (unlikely(ret < 0)) {
        s->state = ret;
        lua_pushnil(L);
        if (ret == SSL_ERROR) {
            lua_pushstring(L, ssl_last_error_string(s->ssl, err_buf, sizeof(err_buf)));
            return 2;
        }
        return 1;
    }

    s->state = SSL_OK;

    b->w += ret;
    lua_pushinteger(L, ret);

    return 1;
}

static int eco_ssl_write(lua_State *L)
{
    struct eco_ssl_session *s = luaL_checkudata(L, 1, ECO_SSL_MT);
    static char err_buf[128];
    const char *data;
    int ret = 0;
    size_t len;

    data = luaL_checklstring(L, 2, &len);

    ret = ssl_write(s->ssl, data, len);
    if (unlikely(ret < 0)) {
        s->state = ret;
        lua_pushnil(L);
        if (ret == SSL_ERROR) {
            lua_pushstring(L, ssl_last_error_string(s->ssl, err_buf, sizeof(err_buf)));
            return 2;
        }
        return 1;
    }

    s->state = SSL_OK;

    lua_pushinteger(L, ret);
    return 1;
}

static int eco_ssl_state(lua_State *L)
{
    struct eco_ssl_session *s = luaL_checkudata(L, 1, ECO_SSL_MT);
    lua_pushinteger(L, s->state);
    return 1;
}

static int eco_ssl_session_new(lua_State *L)
{
    struct eco_ssl_context *ctx = luaL_checkudata(L, 1, ECO_SSL_CTX_MT);
    int fd = luaL_checkinteger(L, 2);
    bool insecure = lua_toboolean(L, 3);
    struct eco_ssl_session *s;

    s = lua_newuserdata(L, sizeof(struct eco_ssl_session));
    memset(s, 0, sizeof(struct eco_ssl_session));
    lua_pushvalue(L, lua_upvalueindex(1));
    lua_setmetatable(L, -2);

    s->ssl = ssl_session_new(ctx->ctx, fd);
    s->is_server = ctx->is_server;
    s->insecure = insecure;

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

static int eco_ssl_context_new(lua_State *L)
{
    bool is_server = lua_toboolean(L, 1);
    struct eco_ssl_context *ctx;

    ctx = lua_newuserdata(L, sizeof(struct eco_ssl_context));
    memset(ctx, 0, sizeof(struct eco_ssl_context));
    lua_pushvalue(L, lua_upvalueindex(1));
    lua_setmetatable(L, -2);

    ctx->ctx = ssl_context_new(is_server);
    ctx->is_server = is_server;

    load_default_ca_cert(ctx->ctx);

    return 1;
}

static const struct luaL_Reg ssl_ctx_methods[] =  {
    {"__gc", eco_ssl_context_gc},
    {"free", eco_ssl_context_free},
    {"load_ca_cert_file", eco_ssl_load_ca_cert_file},
    {"load_cert_file", eco_ssl_load_cert_file},
    {"load_key_file", eco_ssl_load_key_file},
    {"set_ciphers", eco_ssl_set_ciphers},
    {"require_validation", eco_ssl_set_require_validation},
    {NULL, NULL}
};

static const struct luaL_Reg ssl_methods[] =  {
    {"__gc", eco_ssl_gc},
    {"free", eco_ssl_free},
    {"set_server_name", eco_ssl_set_server_name},
    {"negotiate", eco_ssl_ssl_negotiate},
    {"read", eco_ssl_read},
    {"read_to_buffer", eco_ssl_read_to_buffer},
    {"write", eco_ssl_write},
    {"state", eco_ssl_state},
    {NULL, NULL}
};

int luaopen_eco_core_ssl(lua_State *L)
{
    lua_newtable(L);

    eco_new_metatable(L, ECO_SSL_CTX_MT, ssl_ctx_methods);

    eco_new_metatable(L, ECO_SSL_MT, ssl_methods);
    lua_pushcclosure(L, eco_ssl_session_new, 1);
    lua_setfield(L, -2, "new");

    lua_pushcclosure(L, eco_ssl_context_new, 1);
    lua_setfield(L, -2, "context");

    return 1;
}
