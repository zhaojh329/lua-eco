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

enum {
    ECO_SSL_OVERTIME    = 1 << 0
};

struct eco_ssl_context {
    struct ssl_context *ctx;
    bool is_server;
};

struct eco_ssl_session {
    struct eco_ssl_context *ctx;
    struct ssl *ssl;
    bool insecure;
    lua_State *co;
    struct ev_timer tmr;
    struct ev_io io;
    uint8_t flags;
    struct {
        size_t len;
        size_t sent;
        const void *data;
    } snd;
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

static void ev_timer_cb(struct ev_loop *loop, ev_timer *w, int revents)
{
    struct eco_ssl_session *s = container_of(w, struct eco_ssl_session, tmr);

    ev_io_stop(loop, &s->io);

    s->flags |= ECO_SSL_OVERTIME;

    eco_resume(s->co, 0);
}

static void ev_io_cb(struct ev_loop *loop, ev_io *w, int revents)
{
    struct eco_ssl_session *s = container_of(w, struct eco_ssl_session, io);

    ev_io_stop(loop, w);
    ev_timer_stop(loop, &s->tmr);
    eco_resume(s->co, 0);
}

static int lua_ssl_free(lua_State *L)
{
    struct eco_ssl_session *s = luaL_checkudata(L, 1, ECO_SSL_MT);
    struct ev_loop *loop = EV_DEFAULT;

    if (!s->ssl)
        return 0;

    ev_timer_stop(loop, &s->tmr);
    ev_io_stop(loop, &s->io);

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

static int lua_ssl_handshakek(lua_State *L, int status, lua_KContext ctx)
{
    struct eco_ssl_session *s = (struct eco_ssl_session *)ctx;
    struct ev_loop *loop = EV_DEFAULT;
    const char *verify_error = NULL;
    char err_buf[128];
    int ret;

    s->co = NULL;

    if (s->flags & ECO_SSL_OVERTIME) {
        lua_pushnil(L);
        lua_pushliteral(L, "timeout");
        return 2;
    }

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

        s->co = L;

        ev_timer_set(&s->tmr, 15.0, 0);
        ev_timer_start(loop, &s->tmr);

        ev_io_modify(&s->io, ret == SSL_WANT_READ ? EV_READ : EV_WRITE);
        ev_io_start(loop, &s->io);

        return lua_yieldk(L, 0, ctx, lua_ssl_handshakek);
    }

    if (verify_error && !s->insecure) {
        lua_pushnil(L);
        lua_pushfstring(L, "SSL certificate verify fail: %s", verify_error);
        return 2;
    }

    lua_pushboolean(L, true);
    return 1;
}

static int lua_ssl_handshake(lua_State *L)
{
    struct eco_ssl_session *s = luaL_checkudata(L, 1, ECO_SSL_MT);

    return lua_ssl_handshakek(L, 0, (lua_KContext)s);
}

static int lua_sendk(lua_State *L, int status, lua_KContext ctx)
{
    struct eco_ssl_session *s = (struct eco_ssl_session *)ctx;
    struct ev_loop *loop = EV_DEFAULT;
    const void *data = s->snd.data;
    size_t sent = s->snd.sent;
    size_t len = s->snd.len;
    char err_buf[128];
    int ret = 0;

    s->co = NULL;

    if (sent == len) {
        lua_pushinteger(L, sent);
        return 1;
    }

    ret = ssl_write(s->ssl, data, len - sent);
    if (unlikely(ret < 0)) {
        if (ret == SSL_ERROR) {
            lua_pushnil(L);
            lua_pushstring(L, ssl_last_error_string(s->ssl, err_buf, sizeof(err_buf)));
            return 2;
        }
        goto again;
    }

    s->snd.sent += ret;
    s->snd.data += ret;

again:
    s->co = L;
    ev_io_modify(&s->io, ret == SSL_WANT_READ ? EV_READ : EV_WRITE);
    ev_io_start(loop, &s->io);
    return lua_yieldk(L, 0, ctx, lua_sendk);
}

static int lua_send(lua_State *L)
{
    struct eco_ssl_session *s = luaL_checkudata(L, 1, ECO_SSL_MT);

    if (!s->ssl) {
        lua_pushnil(L);
        lua_pushliteral(L, "closed");
        return 2;
    }

    if (s->co) {
        lua_pushnil(L);
        lua_pushliteral(L, "busy");
        return 2;
    }

    s->snd.data = luaL_checklstring(L, 2, &s->snd.len);
    s->snd.sent = 0;

    return lua_sendk(L, 0, (lua_KContext)s);
}

static int bufio_fill_ssl(struct eco_bufio *b, lua_State *L, lua_KContext ctx, lua_KFunction k)
{
    struct eco_ssl_session *s = (struct eco_ssl_session *)b->ctx;
    struct ev_loop *loop = EV_DEFAULT;
    static char err_buf[128];
    ssize_t ret;

    buffer_slide(b);

    if (buffer_room(b) == 0) {
        b->error = "buffer is full";
        return -1;
    }

    ret = ssl_read(s->ssl, b->data + b->w, buffer_room(b));
    if (unlikely(ret < 0)) {
        if (ret == SSL_ERROR) {
            b->error = ssl_last_error_string(s->ssl, err_buf, sizeof(err_buf));
            return -1;
        }

        b->co = L;

        if (b->timeout > 0) {
            ev_timer_set(&b->tmr, b->timeout, 0);
            ev_timer_start(loop, &b->tmr);
        }

        ev_io_modify(&b->io, ret == SSL_WANT_READ ? EV_READ : EV_WRITE);
        ev_io_start(loop, &b->io);
        return lua_yieldk(L, 0, ctx, k);
    }

    if (ret == 0) {
        b->flags.eof = 1;
        b->error = "closed";
        return -1;
    }

    b->w += ret;

    return ret;
}

static int lua_ssl_session_new(lua_State *L)
{
    struct eco_ssl_context *ctx = luaL_checkudata(L, 1, ECO_SSL_CTX_MT);
    int fd = luaL_checkinteger(L, 2);
    bool insecure = lua_toboolean(L, 3);
    struct eco_ssl_session *s;

    s = lua_newuserdata(L, sizeof(struct eco_ssl_session));
    memset(s, 0, sizeof(struct eco_ssl_session));
    lua_pushvalue(L, lua_upvalueindex(1));
    lua_setmetatable(L, -2);

    memset(s, 0, sizeof(struct eco_ssl_session));

    s->ssl = ssl_session_new(ctx->ctx, fd);
    s->insecure = insecure;
    s->ctx = ctx;

    ev_timer_init(&s->tmr, ev_timer_cb, 0.0, 0);
    ev_io_init(&s->io, ev_io_cb, fd, 0);

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
    lua_pushvalue(L, lua_upvalueindex(1));
    lua_setmetatable(L, -2);

    ctx->ctx = ssl_context_new(is_server);
    ctx->is_server = is_server;

    load_default_ca_cert(ctx->ctx);

    return 1;
}

static const struct luaL_Reg ssl_ctx_methods[] =  {
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
    {"send", lua_send},
    {"write", lua_send},
    {NULL, NULL}
};

static const struct luaL_Reg ssl_mt[] =  {
    {"__gc", lua_ssl_free},
    {"__close", lua_ssl_free},
    {NULL, NULL}
};

int luaopen_eco_core_ssl(lua_State *L)
{
    lua_newtable(L);

    lua_add_constant(L, "OK", SSL_OK);
    lua_add_constant(L, "ERROR", SSL_ERROR);
    lua_add_constant(L, "WANT_READ", SSL_WANT_READ);
    lua_add_constant(L, "WANT_WRITE", SSL_WANT_WRITE);
    lua_add_constant(L, "INSECURE", SSL_INSECURE);

    lua_pushlightuserdata(L, bufio_fill_ssl);
    lua_setfield(L, -2, "bufio_fill");

    eco_new_metatable(L, ECO_SSL_CTX_MT, ssl_ctx_mt, ssl_ctx_methods);
    luaL_getsubtable(L, -1, "__index");

    eco_new_metatable(L, ECO_SSL_MT, ssl_mt, ssl_methods);
    lua_pushcclosure(L, lua_ssl_session_new, 1);
    lua_setfield(L, -2, "new");
    lua_pop(L, 1);

    lua_pushcclosure(L, lua_ssl_context_new, 1);
    lua_setfield(L, -2, "context");

    return 1;
}
