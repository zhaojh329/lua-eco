/*
 * MIT License
 *
 * Copyright (c) 2022 Jianhui Zhao <zhaojh329@gmail.com>
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

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
    struct eco_context *eco;
    struct ssl_context *cxt;
    bool ssl_negotiated;
    struct ev_timer tmr;
    struct ev_io ior;
    struct ev_io iow;
    bool is_server;
    bool insecure;
    lua_State *co;
    void *ssl;
    int fd;
    struct {
        struct eco_buf *b;
        double timeout;
        size_t need;
        char eol;
    } reader;

    struct {
        const char *data;
        size_t left;
        size_t len;
    } writer;
};

static int eco_ssl_context_gc(lua_State *L)
{
    struct eco_ssl_context *ctx = lua_touserdata(L, 1);
    ssl_context_free(ctx->ctx);
    return 0;
}

static void on_ssl_verify_error(int error, const char *str, void *arg)
{
    bool *valid_cert = arg;

    *valid_cert = false;
}

/* -1 error, 0 pending, 1 ok */
static int ssl_negotiated(struct eco_ssl_session *s, char *err_buf, int errbuf_len)
{
    bool valid_cert = true;
    int ret;

    if (s->is_server)
        ret = ssl_accept(s->ssl, on_ssl_verify_error, &valid_cert);
    else
        ret = ssl_connect(s->ssl, on_ssl_verify_error, &valid_cert);

    if (ret == SSL_PENDING)
        return 0;

    if (ret == SSL_ERROR) {
        ssl_last_error_string(err_buf, errbuf_len);
        return -1;
    }

    if (!valid_cert && !s->insecure) {
        snprintf(err_buf, errbuf_len, "SSL certificate verify fail");
        return -1;
    }

    s->ssl_negotiated = true;

    return 1;
}

static void eco_ssl_timer_cb(struct ev_loop *loop, ev_timer *w, int revents)
{
    struct eco_ssl_session *s = container_of(w, struct eco_ssl_session, tmr);
    struct eco_context *eco = s->eco;
    lua_State *co = s->co;

    ev_io_stop(loop, &s->ior);
    ev_io_stop(loop, &s->iow);

    lua_pushnil(co);
    lua_pushliteral(co, "timeout");
    eco_resume(eco->L, co, 2);
}

/*
** Return value:
**  0: need read actually
** -1: error
**  1: success
*/
static int eco_ssl_read_from_buf(struct eco_ssl_session *s, lua_State *L)
{
    struct eco_buf *b = s->reader.b;
    char eol = s->reader.eol;
    size_t ate = 0;

    if (unlikely(!b))
        return 0;

    if (s->reader.need > 0 || eol) {
        if (eol) {
            char *pos = memchr(b->data, '\n', b->len);
            if (pos)
                ate = pos - b->data + 1;
        } else if (b->len >= s->reader.need) {
            ate = s->reader.need;
        }

        if (ate == 0 && (b->size - b->len == 0)) {
            lua_pushnil(L);
            lua_pushliteral(L, "buffer is full");
            return -1;
        }
    } else if (b->len > 0) {
        ate = b->len;
    }

    if (ate > 0) {
        b->len -= ate;

        if (eol == 'l')
            lua_pushlstring(L, b->data, ate - 1);
        else
            lua_pushlstring(L, b->data, ate);

        memmove(b->data, b->data + ate, b->len);
        return 1;
    }

    return 0;
}

static void eco_ssl_read_cb(struct ev_loop *loop, ev_io *w, int revents)
{
    struct eco_ssl_session *s = container_of(w, struct eco_ssl_session, ior);
    struct eco_context *eco = s->eco;
    static char err_buf[128];
    lua_State *co = s->co;
    struct eco_buf *b;
    int narg = 1;
    ssize_t r;

    if (unlikely(!s->ssl_negotiated)) {
        r = ssl_negotiated(s, err_buf, sizeof(err_buf));
        if (r < 0) {
            narg++;
            lua_pushnil(co);
            lua_pushstring(co, err_buf);
            goto done;
        }
        if (r == 0)
            return;
    }

    if (unlikely(!s->reader.b)) {
        size_t size = getpagesize();
        s->reader.b = malloc(sizeof(struct eco_buf) + size);
        if (!s->reader.b) {
            narg++;
            lua_pushnil(co);
            lua_pushstring(co, strerror(errno));
            goto done;
        }
        s->reader.b->size = size;
        s->reader.b->len = 0;
    }

    b = s->reader.b;

    r = ssl_read(s->ssl, b->data + b->len, b->size - b->len);
    if (unlikely(r < 0)) {
        if (r == SSL_PENDING)
            return;
        narg++;
        lua_pushnil(co);
        lua_pushstring(co, ssl_last_error_string(err_buf, sizeof(err_buf)));
    } else if (r == 0) {
        if (b->len > 0) {
            lua_pushlstring(co, b->data, b->len);
            b->len = 0;
        } else {
            narg++;
            lua_pushnil(co);
            lua_pushliteral(co, "closed");
        }
    } else {
        b->len += r;
        r = eco_ssl_read_from_buf(s, co);
        if (r == 0)
            return;
        if (r < 0)
            narg++;
    }

done:
    ev_io_stop(loop, w);
    ev_timer_stop(loop, &s->tmr);
    eco_resume(eco->L, co, narg);
}

static void eco_ssl_write_cb(struct ev_loop *loop, ev_io *w, int revents)
{
    struct eco_ssl_session *s = container_of(w, struct eco_ssl_session, iow);
    static char err_buf[128];
    lua_State *co = s->co;
    int narg = 1;
    ssize_t r;

    if (unlikely(!s->ssl_negotiated)) {
        r = ssl_negotiated(s, err_buf, sizeof(err_buf));
        if (r < 0) {
            narg++;
            lua_pushnil(co);
            lua_pushstring(co, err_buf);
            goto done;
        }
        if (r == 0)
            return;
    }

    r = ssl_write(s->ssl, s->writer.data, s->writer.left);
    if (unlikely(r < 0)) {
        if (r == SSL_PENDING)
            return;
        narg++;
        lua_pushuint(co, s->writer.len - s->writer.left);
        lua_pushstring(co, ssl_last_error_string(err_buf, sizeof(err_buf)));
        goto done;
    }

    s->writer.data += r;
    s->writer.left -= r;

    if (s->writer.left > 0)
        return;
    lua_pushuint(co, s->writer.len);

done:
    ev_io_stop(loop, w);
    eco_resume(s->eco->L, co, narg);
}

static int eco_ssl_gc(lua_State *L)
{
    struct eco_ssl_session *s = lua_touserdata(L, 1);
    ssl_session_free(s->ssl);
    free(s->reader.b);
    return 0;
}

static int eco_ssl_settimeout(lua_State *L)
{
    struct eco_ssl_session *s = lua_touserdata(L, 1);
    s->reader.timeout = luaL_checknumber(L, 2);
    return 0;
}

static int eco_ssl_set_server_name(lua_State *L)
{
    struct eco_ssl_session *s = lua_touserdata(L, 1);
    const char *name = luaL_checkstring(L, 2);

    ssl_set_server_name(s->ssl, name);

    return 0;
}

static int eco_ssl_read(lua_State *L)
{
    struct eco_ssl_session *s = lua_touserdata(L, 1);
    struct ev_loop *loop = s->eco->loop;
    int r;

    s->reader.need = 0;
    s->reader.eol = 0;

    if (lua_gettop(L) > 1) {
        if (lua_isnumber(L, 2)) {
            size_t need = lua_tointeger(L, 2);
            if (unlikely(need == 0)) {
                lua_pushliteral(L, "");
                return 1;
            }
            s->reader.need = need;
        } else if (lua_isstring(L, 2)) {
            const char *eol = lua_tostring(L, 2);
            if (*eol == 'l' || *eol == 'L')
                s->reader.eol = *eol;
        }
    }

    r = eco_ssl_read_from_buf(s, L);
    if (r < 0)
        return 2;
    else if (r > 0)
        return 1;

    if (s->reader.timeout > 0) {
        ev_timer_set(&s->tmr, s->reader.timeout, 0);
        ev_timer_start(loop, &s->tmr);
    }

    s->co = L;

    ev_io_start(loop, &s->ior);

    return lua_yield(L, 0);
}

static int eco_ssl_write(lua_State *L)
{
    struct eco_ssl_session *s = lua_touserdata(L, 1);
    static char err_buf[128];
    const char *data;
    size_t len;
    int ret = 0;

    data = luaL_checklstring(L, 2, &len);

    if (s->ssl_negotiated) {
        ret = ssl_write(s->ssl, data, len);
        if (unlikely(ret == SSL_ERROR)) {
            lua_pushnil(L);
            lua_pushstring(L, ssl_last_error_string(err_buf, sizeof(err_buf)));
            return 2;
        }
    }

    if (likely(ret == len)) {
        lua_pushuint(L, len);
        return 1;
    }

    s->writer.data = data + ret;
    s->writer.left = len - ret;
    s->writer.len = len;
    s->co = L;

    ev_io_start(s->eco->loop, &s->iow);

    return lua_yield(L, 0);
}

static int eco_ssl_session_new(lua_State *L)
{
    struct eco_context *eco = eco_check_context(L);
    struct eco_ssl_context *ctx = lua_touserdata(L, 1);
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
    s->eco = eco;
    s->fd = fd;

    ev_init(&s->tmr, eco_ssl_timer_cb);
    ev_io_init(&s->ior, eco_ssl_read_cb, fd, EV_READ);
    ev_io_init(&s->iow, eco_ssl_write_cb, fd, EV_WRITE);

    return 1;
}

static int eco_ssl_load_ca_crt_file(lua_State *L)
{
    struct eco_ssl_context *ctx = lua_touserdata(L, 1);
    const char *file = luaL_checkstring(L, 2);

    lua_pushboolean(L, !!!ssl_load_ca_crt_file(ctx->ctx, file));
    return 1;
}

static int eco_ssl_load_crt_file(lua_State *L)
{
    struct eco_ssl_context *ctx = lua_touserdata(L, 1);
    const char *file = luaL_checkstring(L, 2);

    lua_pushboolean(L, !!!ssl_load_crt_file(ctx->ctx, file));
    return 1;
}

static int eco_ssl_load_key_file(lua_State *L)
{
    struct eco_ssl_context *ctx = lua_touserdata(L, 1);
    const char *file = luaL_checkstring(L, 2);

    lua_pushboolean(L, !!!ssl_load_key_file(ctx->ctx, file));
    return 1;
}

static int eco_ssl_set_ciphers(lua_State *L)
{
    struct eco_ssl_context *ctx = lua_touserdata(L, 1);
    const char *ciphers = luaL_checkstring(L, 2);

    lua_pushboolean(L, !!!ssl_set_ciphers(ctx->ctx, ciphers));
    return 1;
}

static int eco_ssl_set_require_validation(lua_State *L)
{
    struct eco_ssl_context *ctx = lua_touserdata(L, 1);
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
		ssl_load_ca_crt_file(ctx, gl.gl_pathv[i]);

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

static const struct luaL_Reg ssl_ctx_metatable[] =  {
    {"__gc", eco_ssl_context_gc},
    {"load_ca_crt_file", eco_ssl_load_ca_crt_file},
    {"load_crt_file", eco_ssl_load_crt_file},
    {"load_key_file", eco_ssl_load_key_file},
    {"set_ciphers", eco_ssl_set_ciphers},
    {"require_validation", eco_ssl_set_require_validation},
    {NULL, NULL}
};

static const struct luaL_Reg ssl_metatable[] =  {
    {"__gc", eco_ssl_gc},
    {"settimeout", eco_ssl_settimeout},
    {"set_server_name", eco_ssl_set_server_name},
    {"read", eco_ssl_read},
    {"write", eco_ssl_write},
    {NULL, NULL}
};

int luaopen_eco_ssl(lua_State *L)
{
    lua_newtable(L);

    eco_new_metatable(L, ssl_ctx_metatable);

    eco_new_metatable(L, ssl_metatable);
    lua_pushcclosure(L, eco_ssl_session_new, 1);
    lua_setfield(L, -2, "new");

    lua_pushcclosure(L, eco_ssl_context_new, 1);
    lua_setfield(L, -2, "context");

    return 1;
}
