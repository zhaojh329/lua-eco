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

#include <netinet/tcp.h>
#include <sys/socket.h>
#include <arpa/inet.h>
#include <stdlib.h>
#include <sys/un.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>

#include "eco.h"

enum {
    ECO_SOCKET_TYPE_TCP = 1,
    ECO_SOCKET_TYPE_UDP,
    ECO_SOCKET_TYPE_UNIX,
    ECO_SOCKET_TYPE_UNIX_DGRAM
};

enum {
    ECO_SOCKET_FLAG_CONNECTED = (1 << 0),
    ECO_SOCKET_FLAG_ACCEPTED = (1 << 1)
};

struct eco_socket {
    struct eco_context *ctx;
    struct ev_timer tmr;
    struct ev_io ior;
    struct ev_io iow;
    lua_State *co;
    uint8_t flag;
    int fd;

    double connect_timeout;
    int domain;

    struct {
        union {
            struct sockaddr_un un;
            struct sockaddr_in in;
            struct sockaddr_in6 in6;
        } from;
        bool use_recvfrom;
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

struct eco_socket_opt {
    const char *name;
    int (*func)(lua_State *L, int fd);
};

static char socket_established_metatable_key;

static inline bool eco_socket_has_flag(struct eco_socket *sock, int flag)
{
    return (sock->flag & flag) != 0;
}

static void push_sockaddr(lua_State *L, const struct sockaddr *addr)
{
    lua_newtable(L);

    if (addr->sa_family == AF_INET) {
        struct sockaddr_in *in = (struct sockaddr_in *)addr;
        char buf[INET_ADDRSTRLEN];

        lua_pushstring(L, inet_ntop(AF_INET, &in->sin_addr, buf, sizeof(buf)));
        lua_setfield(L, -2, "ipaddr");

        lua_pushinteger(L, ntohs(in->sin_port));
        lua_setfield(L, -2, "port");

        lua_pushstring(L, "inet");
    } else if (addr->sa_family == AF_INET6) {
        struct sockaddr_in6 *in6 = (struct sockaddr_in6 *)addr;
        char buf[INET6_ADDRSTRLEN];

        lua_pushstring(L, inet_ntop(AF_INET6, &in6->sin6_addr, buf, sizeof(buf)));
        lua_setfield(L, -2, "ipaddr");

        lua_pushinteger(L, ntohs(in6->sin6_port));
        lua_setfield(L, -2, "port");

        lua_pushstring(L, "inet6");
    } else if (addr->sa_family == AF_UNIX) {
        struct sockaddr_un *un = (struct sockaddr_un *)addr;

        lua_pushstring(L, un->sun_path);
        lua_setfield(L, -2, "path");

        lua_pushstring(L, "unix");
    } else {
        return;
    }

    lua_setfield(L, -2, "family");
}

static socklen_t parse_address(lua_State *L, int first,
    struct eco_socket *sock, struct sockaddr *saddr, const char **err)
{
    saddr->sa_family = sock->domain;

    if (sock->domain == AF_UNIX) {
        struct sockaddr_un *un = (struct sockaddr_un *)saddr;
        const char *path = luaL_checkstring(L, first);

        if (strlen(path) >= sizeof(un->sun_path)) {
            *err = "path too long";
            return 0;
        }

        strcpy(un->sun_path, path);
        return SUN_LEN(un);
    } else {
        const char *addr = lua_tostring(L, first++);
        int port = luaL_checkinteger(L, first);

        if (sock->domain == AF_INET) {
            struct sockaddr_in *in = (struct sockaddr_in *)saddr;

            if (addr && inet_pton(AF_INET, addr, &in->sin_addr) != 1) {
                *err = "not a valid IPv4 address";
                return 0;
            }

            in->sin_port = htons(port);
            return sizeof(struct sockaddr_in);
        } else {
            struct sockaddr_in6 *in6 = (struct sockaddr_in6 *)saddr;

            if (addr && inet_pton(AF_INET6, addr, &in6->sin6_addr) != 1) {
                *err = "not a valid IPv6 address";
                return 0;
            }

            in6->sin6_port = htons(port);
            return sizeof(struct sockaddr_in6);
        }
    }
}

static void eco_socket_timer_cb(struct ev_loop *loop, ev_timer *w, int revents)
{
    struct eco_socket *sock = container_of(w, struct eco_socket, tmr);
    struct eco_context *ctx = sock->ctx;
    lua_State *co = sock->co;

    ev_io_stop(loop, &sock->ior);
    ev_io_stop(loop, &sock->iow);

    if (!eco_socket_has_flag(sock, ECO_SOCKET_FLAG_CONNECTED))
        lua_pushboolean(co, false);
    else
        lua_pushnil(co);

    lua_pushliteral(co, "timeout");
    eco_resume(ctx->L, co, 2);
}

/*
** Return value:
**  0: need read actually
** -1: error
**  1: success
*/
static int eco_socket_read_from_buf(struct eco_socket *sock, lua_State *L)
{
    struct eco_buf *b = sock->reader.b;
    char eol = sock->reader.eol;
    size_t ate = 0;

    if (unlikely(!b))
        return 0;

    if (sock->reader.need > 0 || eol) {
        if (eol) {
            char *pos = memchr(b->data, '\n', b->len);
            if (pos)
                ate = pos - b->data + 1;
        } else if (b->len >= sock->reader.need) {
            ate = sock->reader.need;
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

static void eco_socket_read_cb(struct ev_loop *loop, ev_io *w, int revents)
{
    struct eco_socket *sock = container_of(w, struct eco_socket, ior);
    struct eco_context *ctx = sock->ctx;
    lua_State *co = sock->co;
    socklen_t addrlen = 0;
    struct eco_buf *b;
    int narg = 1;
    ssize_t r;

    if (unlikely(!sock->reader.b)) {
        size_t size = getpagesize();
        sock->reader.b = malloc(sizeof(struct eco_buf) + size);
        if (!sock->reader.b) {
            narg++;
            lua_pushnil(co);
            lua_pushstring(co, strerror(errno));
            goto done;
        }
        sock->reader.b->size = size;
        sock->reader.b->len = 0;
    }

    b = sock->reader.b;

    if (unlikely(sock->reader.use_recvfrom)) {
        memset(&sock->reader.from, 0, sizeof(sock->reader.from));

        if (sock->domain == AF_UNIX)
            addrlen = sizeof(struct sockaddr_un);
        else if (sock->domain == AF_INET)
            addrlen = sizeof(struct sockaddr_in);
        else
            addrlen = sizeof(struct sockaddr_in6);

        r = recvfrom(w->fd, b->data, b->size, 0,
            (struct sockaddr *)&sock->reader.from, &addrlen);
        if (r < 0) {
            narg++;
            lua_pushnil(co);
            lua_pushstring(co, strerror(errno));
        } else {
            lua_pushlstring(co, b->data, r);
        }
    } else {
        r = read(w->fd, b->data + b->len, b->size - b->len);
        if (r < 0) {
            narg++;
            lua_pushnil(co);
            lua_pushstring(co, strerror(errno));
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
            r = eco_socket_read_from_buf(sock, co);
            if (r == 0)
                return;
            if (r < 0)
                narg++;
        }
    }

done:
    ev_io_stop(loop, w);
    ev_timer_stop(loop, &sock->tmr);
    eco_resume(ctx->L, co, narg);
}

static void eco_socket_write_cb(struct ev_loop *loop, ev_io *w, int revents)
{
    struct eco_socket *sock = container_of(w, struct eco_socket, iow);
    lua_State *L = sock->ctx->L;
    lua_State *co = sock->co;

    if (unlikely(!eco_socket_has_flag(sock, ECO_SOCKET_FLAG_CONNECTED))) {
        int err = 0, narg = 1;
        socklen_t len = sizeof(err);

        ev_io_stop(loop, w);
        ev_timer_stop(loop, &sock->tmr);

        if (getsockopt(w->fd, SOL_SOCKET, SO_ERROR, &err, &len))
            err = errno;

        if (err) {
            narg++;
            lua_pushboolean(co, false);
            lua_pushstring(co, strerror(err));
        } else {
            sock->flag |= ECO_SOCKET_FLAG_CONNECTED;
            lua_pushboolean(L, true);
            lua_xmove(L, co, 1);
        }

        eco_resume(L, co, narg);
        return;
    }

    if (sock->writer.left) {
        ssize_t ret = write(w->fd, sock->writer.data, sock->writer.left);
        if (ret < 0) {
            lua_pushuint(co, sock->writer.len - sock->writer.left);
            lua_pushstring(co, strerror(errno));
            ev_io_stop(loop, w);
            eco_resume(L, co, 2);
            return;
        }

        sock->writer.data += ret;
        sock->writer.left -= ret;

        if (sock->writer.left == 0) {
            ev_io_stop(loop, w);
            lua_pushuint(co, sock->writer.len);
            eco_resume(L, co, 1);
        }
    }
}

static void eco_socket_accept_cb(struct ev_loop *loop, ev_io *w, int revents)
{
    struct eco_socket *sock = container_of(w, struct eco_socket, ior);
    struct eco_context *ctx = sock->ctx;
    struct eco_socket *cli;
    lua_State *co = sock->co;
    lua_State *L = ctx->L;
    int fd;

    ev_io_stop(loop, w);

    fd = accept4(sock->fd, NULL, NULL, SOCK_NONBLOCK);
    if (fd < 0) {
        lua_pushnil(co);
        lua_pushstring(co, strerror(errno));
        eco_resume(ctx->L, co, 2);
        return;
    }

    cli = lua_newuserdata(L, sizeof(struct eco_socket));
    lua_pushlightuserdata(L, &socket_established_metatable_key);
    lua_rawget(L, LUA_REGISTRYINDEX);
    lua_setmetatable(L, -2);

    memset(cli, 0, sizeof(struct eco_socket));

    ev_init(&cli->tmr, eco_socket_timer_cb);
    ev_io_init(&cli->ior, eco_socket_read_cb, fd, EV_READ);
    ev_io_init(&cli->iow, eco_socket_write_cb, fd, EV_WRITE);

    cli->ctx = ctx;
    cli->fd = fd;
    cli->flag |= ECO_SOCKET_FLAG_ACCEPTED;

    lua_xmove(L, co, 1);
    eco_resume(L, co, 1);
}

static int eco_socket_getfd(lua_State *L)
{
    struct eco_socket *sock = lua_touserdata(L, 1);
    lua_pushinteger(L, sock->fd);
    return 1;
}

static int eco_socket_recv(lua_State *L)
{
    struct eco_socket *sock = lua_touserdata(L, 1);
    struct ev_loop *loop = sock->ctx->loop;
    int r;

    if (unlikely(sock->fd < 0)) {
        lua_pushnil(L);
        lua_pushliteral(L, "closed");
        return 2;
    }

    sock->reader.need = 0;
    sock->reader.eol = 0;

    if (lua_gettop(L) > 1) {
        if (lua_isnumber(L, 2)) {
            size_t need = lua_tointeger(L, 2);
            if (unlikely(need == 0)) {
                lua_pushliteral(L, "");
                return 1;
            }
            sock->reader.need = need;
        } else if (lua_isstring(L, 2)) {
            const char *eol = lua_tostring(L, 2);
            if (*eol == 'l' || *eol == 'L')
                sock->reader.eol = *eol;
        }
    }

    r = eco_socket_read_from_buf(sock, L);
    if (r < 0)
        return 2;
    else if (r > 0)
        return 1;

    if (sock->reader.timeout > 0) {
        ev_timer_set(&sock->tmr, sock->reader.timeout, 0);
        ev_timer_start(loop, &sock->tmr);
    }

    sock->co = L;
    sock->reader.use_recvfrom = false;

    ev_io_start(loop, &sock->ior);

    return lua_yield(L, 0);
}

static int eco_socket_send(lua_State *L)
{
    struct eco_socket *sock = lua_touserdata(L, 1);
    struct ev_loop *loop = sock->ctx->loop;
    const char *data;
    size_t len;
    int ret;

    data = luaL_checklstring(L, 2, &len);

    if (unlikely(sock->fd < 0)) {
        lua_pushnil(L);
        lua_pushliteral(L, "closed");
        return 2;
    }

    ret = write(sock->fd, data, len);
    if (unlikely(ret < 0)) {
        lua_pushnil(L);
        lua_pushstring(L, strerror(errno));
        return 2;
    }

    if (likely(ret == len)) {
        lua_pushinteger(L, len);
        return 1;
    }

    sock->writer.data = data + ret;
    sock->writer.left = len - ret;
    sock->writer.len = len;
    sock->co = L;

    ev_io_start(loop, &sock->iow);

    return lua_yield(L, 0);
}

static int eco_socket_recvfrom(lua_State *L)
{
    struct eco_socket *sock = lua_touserdata(L, 1);
    struct ev_loop *loop = sock->ctx->loop;

    if (unlikely(sock->fd < 0)) {
        lua_pushnil(L);
        lua_pushliteral(L, "closed");
        return 2;
    }

    if (sock->reader.timeout > 0) {
        ev_timer_set(&sock->tmr, sock->reader.timeout, 0);
        ev_timer_start(loop, &sock->tmr);
    }

    sock->co = L;
    sock->reader.use_recvfrom = true;

    ev_io_start(loop, &sock->ior);

    return lua_yield(L, 0);
}

static int eco_socket_sendto(lua_State *L)
{
    struct eco_socket *sock = lua_touserdata(L, 1);
    union {
        struct sockaddr_un un;
        struct sockaddr_in in;
        struct sockaddr_in6 in6;
    } dest = {};
    const char *data;
    socklen_t addrlen;
    size_t datalen;
    const char *err;
    int ret;

    if (unlikely(sock->fd < 0)) {
        lua_pushnil(L);
        lua_pushliteral(L, "closed");
        return 2;
    }

    data = luaL_checklstring(L, 2, &datalen);

    addrlen = parse_address(L, 3, sock, (struct sockaddr *)&dest, &err);
    if (addrlen == 0) {
        lua_pushnil(L);
        lua_pushstring(L, err);
        return 2;
    }

    ret = sendto(sock->fd, data, datalen, 0, (const struct sockaddr *)&dest, addrlen);
    if (unlikely(ret < 0)) {
        lua_pushnil(L);
        lua_pushstring(L, strerror(errno));
        return 2;
    }

    lua_pushinteger(L, datalen);
    return 1;
}

static int eco_socke_settimeout(lua_State *L)
{
    struct eco_socket *sock = lua_touserdata(L, 1);
    const char *type = luaL_checkstring(L, 2);
    double timeout = luaL_checknumber(L, 3);

    switch (*type)
    {
    case 'c':
        sock->connect_timeout = timeout;
        break;
    case 'r':
        sock->reader.timeout = timeout;
        break;
    default:
        break;
    }

    return 0;
}

static int __eco_socket_getsockname(lua_State *L, bool peer)
{
    struct eco_socket *sock = lua_touserdata(L, 1);
    struct sockaddr_storage addr = {};
    socklen_t addrlen = sizeof(addr);
    int ret;

    if (peer)
        ret = getpeername(sock->fd, (struct sockaddr *)&addr, &addrlen);
    else
        ret = getsockname(sock->fd, (struct sockaddr *)&addr, &addrlen);
    if (ret) {
        lua_pushnil(L);
        lua_pushstring(L, strerror(errno));
        return 2;
    }

    push_sockaddr(L, (const struct sockaddr *)&addr);

    return 1;
}

static int eco_socket_getsockname(lua_State *L)
{
    return __eco_socket_getsockname(L, false);
}

static int eco_socket_getpeername(lua_State *L)
{
    return __eco_socket_getsockname(L, true);
}

static int eco_socket_close(lua_State *L)
{
    struct eco_socket *sock = lua_touserdata(L, 1);
    struct ev_loop *loop = sock->ctx->loop;
    struct sockaddr_storage addr = {};
    socklen_t addrlen = sizeof(addr);
    int ret;

    if (sock->fd < 0)
        return 0;

    ret = getsockname(sock->fd, (struct sockaddr *)&addr, &addrlen);
    if (!ret && addr.ss_family == AF_UNIX &&
        !eco_socket_has_flag(sock, ECO_SOCKET_FLAG_ACCEPTED)) {
        struct sockaddr_un *un = (struct sockaddr_un *)&addr;

        if (!access(un->sun_path, F_OK))
            unlink(un->sun_path);
    }

    ev_timer_stop(loop, &sock->tmr);
    ev_io_stop(loop, &sock->ior);
    ev_io_stop(loop, &sock->iow);
    close(sock->fd);

    free(sock->reader.b);

    sock->fd = -1;

    return 0;
}

static int eco_socket_destroy(lua_State *L)
{
    eco_socket_close(L);

    return 0;
}

static int eco_socket_bind(lua_State *L)
{
    struct eco_socket *sock = lua_touserdata(L, 1);
    union {
        struct sockaddr_un un;
        struct sockaddr_in in;
        struct sockaddr_in6 in6;
    } addr = {};
    const char *err;
    socklen_t addrlen;

    addrlen = parse_address(L, 2, sock, (struct sockaddr *)&addr, &err);
    if (addrlen == 0) {
        lua_pushboolean(L, false);
        lua_pushstring(L, err);
        return 2;
    }

    if (bind(sock->fd, (struct sockaddr *)&addr, addrlen)) {
        lua_pushboolean(L, false);
        lua_pushstring(L, strerror(errno));
        return 2;
    }

    lua_pushboolean(L, true);
    return 1;
}

static int eco_socket_connect(lua_State *L)
{
    struct eco_socket *sock = lua_touserdata(L, 1);
    struct ev_loop *loop = sock->ctx->loop;
    union {
        struct sockaddr_un un;
        struct sockaddr_in in;
        struct sockaddr_in6 in6;
    } addr = {};
    const char *err;
    socklen_t addrlen;
    bool inprogress = false;

    addrlen = parse_address(L, 2, sock, (struct sockaddr *)&addr, &err);
    if (addrlen == 0) {
        lua_pushboolean(L, false);
        lua_pushstring(L, err);
        return 2;
    }

    if (connect(sock->fd, (struct sockaddr *)&addr, addrlen)) {
        if (errno != EINPROGRESS) {
            lua_pushboolean(L, false);
            lua_pushstring(L, strerror(errno));
            return 2;
        }
        inprogress = true;
    }

    ev_io_init(&sock->ior, eco_socket_read_cb, sock->fd, EV_READ);
    ev_io_init(&sock->iow, eco_socket_write_cb, sock->fd, EV_WRITE);

    sock->ctx = eco_get_context(L);
    sock->co = L;

    if (inprogress) {
        if (sock->connect_timeout > 0) {
            ev_timer_set(&sock->tmr, sock->connect_timeout, 0);
            ev_timer_start(loop, &sock->tmr);
        }
        ev_io_start(loop, &sock->iow);
        return lua_yield(L, 0);
    }

    sock->flag |= ECO_SOCKET_FLAG_CONNECTED;

    lua_pushboolean(L, true);
    return 1;
}

static int eco_socket_listen(lua_State *L)
{
    struct eco_socket *sock = lua_touserdata(L, 1);

    if (listen(sock->fd, SOMAXCONN)) {
        lua_pushboolean(L, false);
        lua_pushstring(L, strerror(errno));
        return 2;
    }

    ev_io_init(&sock->ior, eco_socket_accept_cb, sock->fd, EV_READ);

    lua_pushboolean(L, true);
    return 1;
}

static int eco_socket_accept(lua_State *L)
{
    struct eco_socket *sock = lua_touserdata(L, 1);
    struct ev_loop *loop = sock->ctx->loop;

    sock->co = L;
    ev_io_start(loop, &sock->ior);

    return lua_yield(L, 0);
}

static int eco_socket_create(lua_State *L, int domain, int type)
{
    struct eco_context *ctx = eco_check_context(L);
    int protocol = lua_tointeger(L, 1);
    struct eco_socket *sock;
    int fd;

    fd = socket(domain, type | SOCK_NONBLOCK, protocol);
    if (fd < 0) {
        lua_pushnil(L);
        lua_pushstring(L, strerror(errno));
        return 2;
    }

    sock = lua_newuserdata(L, sizeof(struct eco_socket));
    lua_pushvalue(L, lua_upvalueindex(1));
    lua_setmetatable(L, -2);

    memset(sock, 0, sizeof(struct eco_socket));

    ev_init(&sock->tmr, eco_socket_timer_cb);

    if (type == SOCK_DGRAM) {
        ev_io_init(&sock->ior, eco_socket_read_cb, fd, EV_READ);
        ev_io_init(&sock->iow, eco_socket_write_cb, fd, EV_WRITE);
    }

    sock->connect_timeout = 3.0;
    sock->domain = domain;
    sock->ctx = ctx;
    sock->fd = fd;

    return 1;
}

static int eco_socket_tcp(lua_State *L)
{
    return eco_socket_create(L, AF_INET, SOCK_STREAM);
}

static int eco_socket_tcp6(lua_State *L)
{
    return eco_socket_create(L, AF_INET6, SOCK_STREAM);
}

static int eco_socket_udp(lua_State *L)
{
    return eco_socket_create(L, AF_INET, SOCK_DGRAM);
}

static int eco_socket_udp6(lua_State *L)
{
    return eco_socket_create(L, AF_INET6, SOCK_DGRAM);
}

static int eco_socket_unix_stream(lua_State *L)
{
    return eco_socket_create(L, AF_UNIX, SOCK_STREAM);
}

static int eco_socket_unix_dgram(lua_State *L)
{
    return eco_socket_create(L, AF_UNIX, SOCK_DGRAM);
}

static int opt_set(lua_State *L, int fd, int level, int name, void *val, int len)
{
    if (setsockopt(fd, level, name, val, len) < 0) {
        lua_pushboolean(L, false);
        lua_pushstring(L, "setsockopt failed");
        return 2;
    }
    lua_pushboolean(L, true);
    return 1;
}

static int opt_setboolean(lua_State *L, int fd, int level, int name)
{
    int val = lua_toboolean(L, 3);
    return opt_set(L, fd, level, name, &val, sizeof(val));
}

static int opt_setint(lua_State *L, int fd, int level, int name)
{
    int val = (int) lua_tonumber(L, 3);
    return opt_set(L, fd, level, name, &val, sizeof(val));
}

static int opt_set_keepalive(lua_State *L, int fd)
{
    return opt_setboolean(L, fd, SOL_SOCKET, SO_KEEPALIVE);
}

static int opt_set_reuseaddr(lua_State *L, int fd)
{
    return opt_setboolean(L, fd, SOL_SOCKET, SO_REUSEADDR);
}

static int opt_set_reuseport(lua_State *L, int fd)
{
    return opt_setboolean(L, fd, SOL_SOCKET, SO_REUSEPORT);
}

static int opt_set_tcp_nodelay(lua_State *L, int fd)
{
    return opt_setboolean(L, fd, IPPROTO_TCP, TCP_NODELAY);
}

#ifdef TCP_KEEPIDLE
int opt_set_tcp_keepidle(lua_State *L, int fd)
{
    return opt_setint(L, fd, IPPROTO_TCP, TCP_KEEPIDLE);
}
#endif

#ifdef TCP_KEEPCNT
static int opt_set_tcp_keepcnt(lua_State *L, int fd)
{
    return opt_setint(L, fd, IPPROTO_TCP, TCP_KEEPCNT);
}
#endif

#ifdef TCP_KEEPINTVL
static int opt_set_tcp_keepintvl(lua_State *L, int fd)
{
    return opt_setint(L, fd, IPPROTO_TCP, TCP_KEEPINTVL);
}
#endif

static int opt_set_ip6_v6only(lua_State *L, int fd)
{
    return opt_setboolean(L, fd, IPPROTO_IPV6, IPV6_V6ONLY);
}

static int opt_set_linger(lua_State *L, int fd)
{
    struct linger li;

    luaL_checktype(L, 3, LUA_TTABLE);

    lua_getfield(L, 3, "on");
    if (!lua_isboolean(L, -1))
        luaL_argerror(L, 3, "boolean 'on' field expected");

    li.l_onoff = (u_short) lua_toboolean(L, -1);

    lua_getfield(L, 3, "timeout");
    if (!lua_isnumber(L, -1))
        luaL_argerror(L, 3, "number 'timeout' field expected");
    li.l_linger = (u_short) lua_tonumber(L, -1);

    lua_pop(L, 2);
    return opt_set(L, fd, SOL_SOCKET, SO_LINGER, &li, sizeof(li));
}

static int opt_set_dontroute(lua_State *L, int fd)
{
    return opt_setboolean(L, fd, SOL_SOCKET, SO_DONTROUTE);
}

static int opt_set_broadcast(lua_State *L, int fd)
{
    return opt_setboolean(L, fd, SOL_SOCKET, SO_BROADCAST);
}

static int opt_set_ip_multicast_if(lua_State *L, int fd)
{
    const char *address = luaL_checkstring(L, 3);
    struct in_addr val;

    val.s_addr = htonl(INADDR_ANY);

    if (strcmp(address, "*") && !inet_aton(address, &val))
        luaL_argerror(L, 3, "ip expected");

    return opt_set(L, fd, IPPROTO_IP, IP_MULTICAST_IF, &val, sizeof(val));
}

static int opt_set_ip_multicast_ttl(lua_State *L, int fd)
{
    return opt_setint(L, fd, IPPROTO_IP, IP_MULTICAST_TTL);
}

static int opt_set_ip_multicast_loop(lua_State *L, int fd)
{
    return opt_setboolean(L, fd, IPPROTO_IP, IP_MULTICAST_LOOP);
}

static int opt_setmembership(lua_State *L, int fd, int level, int name)
{
    struct ip_mreq val;

    luaL_checktype(L, 3, LUA_TTABLE);

    lua_getfield(L, 3, "multiaddr");
    if (!lua_isstring(L, -1))
        luaL_argerror(L, 3, "string 'multiaddr' field expected");
    if (!inet_aton(lua_tostring(L, -1), &val.imr_multiaddr))
        luaL_argerror(L, 3, "invalid 'multiaddr' ip address");

    lua_getfield(L, 3, "interface");
    if (!lua_isstring(L, -1))
        luaL_argerror(L, 3, "string 'interface' field expected");
    val.imr_interface.s_addr = htonl(INADDR_ANY);
    if (strcmp(lua_tostring(L, -1), "*") &&
            !inet_aton(lua_tostring(L, -1), &val.imr_interface))
        luaL_argerror(L, 3, "invalid 'interface' ip address");

    lua_pop(L, 2);
    return opt_set(L, fd, level, name, &val, sizeof(val));
}

static int opt_set_ip_add_membership(lua_State *L, int fd)
{
    return opt_setmembership(L, fd, IPPROTO_IP, IP_ADD_MEMBERSHIP);
}

static int opt_set_ip_drop_membersip(lua_State *L, int fd)
{
    return opt_setmembership(L, fd, IPPROTO_IP, IP_DROP_MEMBERSHIP);
}

static int opt_set_ip6_unicast_hops(lua_State *L, int fd)
{
    return opt_setint(L, fd, IPPROTO_IPV6, IPV6_UNICAST_HOPS);
}

static int opt_set_ip6_multicast_loop(lua_State *L, int fd)
{
    return opt_setboolean(L, fd, IPPROTO_IPV6, IPV6_MULTICAST_LOOP);
}

static int opt_ip6_setmembership(lua_State *L, int fd, int level, int name)
{
    struct ipv6_mreq val;

    memset(&val, 0, sizeof(val));

    luaL_checktype(L, 3, LUA_TTABLE);

    lua_getfield(L, 3, "multiaddr");
    if (!lua_isstring(L, -1))
        luaL_argerror(L, 3, "string 'multiaddr' field expected");
    if (!inet_pton(AF_INET6, lua_tostring(L, -1), &val.ipv6mr_multiaddr))
        luaL_argerror(L, 3, "invalid 'multiaddr' ip address");

    lua_getfield(L, 3, "interface");
    /* By default we listen to interface on default route
     * (sigh). However, interface= can override it. We should
     * support either number, or name for it. Waiting for
     * windows port of if_nametoindex */
    if (!lua_isnil(L, -1)) {
        if (lua_isnumber(L, -1)) {
            val.ipv6mr_interface = (unsigned int) lua_tonumber(L, -1);
        } else
          luaL_argerror(L, -1, "number 'interface' field expected");
    }

    lua_pop(L, 2);
    return opt_set(L, fd, level, name, &val, sizeof(val));
}

static int opt_set_ip6_add_membership(lua_State *L, int fd)
{
    return opt_ip6_setmembership(L, fd, IPPROTO_IPV6, IPV6_ADD_MEMBERSHIP);
}

static int opt_set_ip6_drop_membersip(lua_State *L, int fd)
{
    return opt_ip6_setmembership(L, fd, IPPROTO_IPV6, IPV6_DROP_MEMBERSHIP);
}

static int opt_set_recv_buf_size(lua_State *L, int fd)
{
    return opt_setint(L, fd, SOL_SOCKET, SO_RCVBUF);
}

static int opt_set_send_buf_size(lua_State *L, int fd)
{
    return opt_setint(L, fd, SOL_SOCKET, SO_SNDBUF);
}

static struct eco_socket_opt optset[] = {
    {"keepalive", opt_set_keepalive},
    {"reuseaddr", opt_set_reuseaddr},
    {"reuseport", opt_set_reuseport},
    {"tcp-nodelay", opt_set_tcp_nodelay},
#ifdef TCP_KEEPIDLE
    {"tcp-keepidle", opt_set_tcp_keepidle},
#endif
#ifdef TCP_KEEPCNT
    {"tcp-keepcnt", opt_set_tcp_keepcnt},
#endif
#ifdef TCP_KEEPINTVL
    {"tcp-keepintvl", opt_set_tcp_keepintvl},
#endif
    {"ipv6-v6only", opt_set_ip6_v6only},
    {"linger", opt_set_linger},
    {"dontroute", opt_set_dontroute},
    {"broadcast", opt_set_broadcast},
    {"ip-multicast-if", opt_set_ip_multicast_if},
    {"ip-multicast-ttl", opt_set_ip_multicast_ttl},
    {"ip-multicast-loop", opt_set_ip_multicast_loop},
    {"ip-add-membership", opt_set_ip_add_membership},
    {"ip-drop-membership", opt_set_ip_drop_membersip},
    {"ipv6-unicast-hops", opt_set_ip6_unicast_hops},
    {"ipv6-multicast-hops", opt_set_ip6_unicast_hops},
    {"ipv6-multicast-loop", opt_set_ip6_multicast_loop},
    {"ipv6-add-membership", opt_set_ip6_add_membership},
    {"ipv6-drop-membership", opt_set_ip6_drop_membersip},
    {"recv-buffer-size", opt_set_recv_buf_size},
    {"send-buffer-size", opt_set_send_buf_size},
    {NULL, NULL}
};

static int eco_socket_setoption(lua_State *L)
{
    struct eco_socket *sock = lua_touserdata(L, 1);
    const char *name = luaL_checkstring(L, 2);
    struct eco_socket_opt *opt = optset;

    while (opt->name && strcmp(name, opt->name))
        opt++;

    if (!opt->func) {
        char msg[57];
        sprintf(msg, "unsupported option `%.35s'", name);
        luaL_argerror(L, 2, msg);
    }

    return opt->func(L, sock->fd);
}

static const struct luaL_Reg socket_metatable[] =  {
    {"setoption", eco_socket_setoption},
    {"getfd", eco_socket_getfd},
    {"recv", eco_socket_recv},
    {"read", eco_socket_recv},
    {"send", eco_socket_send},
    {"write", eco_socket_send},
    {"settimeout", eco_socke_settimeout},
    {"getsockname", eco_socket_getsockname},
    {"getpeername", eco_socket_getpeername},
    {"close", eco_socket_close},
    {"__gc", eco_socket_destroy},
    {NULL, NULL}
};

static void create_socket_metatable(lua_State *L, int type)
{
    eco_new_metatable(L, socket_metatable);

    if (type > 0) {
        lua_pushcfunction(L, eco_socket_bind);
        lua_setfield(L, -2, "bind");

        lua_pushcfunction(L, eco_socket_connect);
        lua_setfield(L, -2, "connect");

        if (type == ECO_SOCKET_TYPE_TCP || type == ECO_SOCKET_TYPE_UNIX) {
            lua_pushcfunction(L, eco_socket_listen);
            lua_setfield(L, -2, "listen");

            lua_pushcfunction(L, eco_socket_accept);
            lua_setfield(L, -2, "accept");
        } else {
            lua_pushcfunction(L, eco_socket_sendto);
            lua_setfield(L, -2, "sendto");

            lua_pushcfunction(L, eco_socket_recvfrom);
            lua_setfield(L, -2, "recvfrom");
        }
    }
}

int luaopen_eco_socket(lua_State *L)
{
    lua_pushlightuserdata(L, &socket_established_metatable_key);
    create_socket_metatable(L, -1);
    lua_rawset(L, LUA_REGISTRYINDEX);

    lua_newtable(L);

    create_socket_metatable(L, ECO_SOCKET_TYPE_TCP);
    lua_pushcclosure(L, eco_socket_tcp, 1);
    lua_setfield(L, -2, "tcp");

    create_socket_metatable(L, ECO_SOCKET_TYPE_TCP);
    lua_pushcclosure(L, eco_socket_tcp6, 1);
    lua_setfield(L, -2, "tcp6");

    create_socket_metatable(L, ECO_SOCKET_TYPE_UDP);
    lua_pushcclosure(L, eco_socket_udp, 1);
    lua_setfield(L, -2, "udp");

    create_socket_metatable(L, ECO_SOCKET_TYPE_UDP);
    lua_pushcclosure(L, eco_socket_udp6, 1);
    lua_setfield(L, -2, "udp6");

    create_socket_metatable(L, ECO_SOCKET_TYPE_UNIX);
    lua_pushcclosure(L, eco_socket_unix_stream, 1);
    lua_setfield(L, -2, "unix");

    create_socket_metatable(L, ECO_SOCKET_TYPE_UNIX_DGRAM);
    lua_pushcclosure(L, eco_socket_unix_dgram, 1);
    lua_setfield(L, -2, "unix_dgram");

    return 1;
}
