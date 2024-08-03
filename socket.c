/* SPDX-License-Identifier: MIT */
/*
 * Author: Jianhui Zhao <zhaojh329@gmail.com>
 */

#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <fcntl.h>

#include <sys/sendfile.h>
#include <sys/socket.h>
#include <arpa/inet.h>
#include <net/if.h>
#include <sys/un.h>

#include <linux/netlink.h>
#include <linux/if_ether.h>
#include <linux/if_arp.h>
#include <netinet/tcp.h>
#include <linux/icmpv6.h>
#include <linux/icmp.h>

#include "eco.h"

#define ECO_SOCKET_MT "eco{socket}"

struct eco_socket {
    struct eco_context *eco;
    struct ev_timer tmr;
    struct {
        uint8_t overtime:1;
        uint8_t established:1;
        uint8_t connecting:1;
    } flag;
    int domain;
    int fd;
    struct {
        struct ev_io io;
        lua_State *co;
        size_t len;
        size_t sent;
        const void *data;
        union {
            struct {
                int fd;
                off_t offset;
            };
            struct {
                uint8_t addr[sizeof(struct sockaddr_un)];
                socklen_t addrlen;
            };
        };
    } snd;
    struct {
        struct ev_io io;
        lua_State *co;
        double timeout;
        bool from;
        size_t len;
        void *buf;
    } rcv;
};

struct sock_opt {
  const char *name;
  int level;
  int opt;
  int (*func)(struct eco_socket *sock, lua_State *L, struct sock_opt *o);
};


static void ev_timer_cb(struct ev_loop *loop, ev_timer *w, int revents)
{
    struct eco_socket *sock = container_of(w, struct eco_socket, tmr);

    sock->flag.overtime = 1;

    if (sock->flag.connecting) {
        ev_io_stop(loop, &sock->snd.io);
        eco_resume(sock->eco->L, sock->snd.co, 0);
    } else {
        ev_io_stop(loop, &sock->rcv.io);
        eco_resume(sock->eco->L, sock->rcv.co, 0);
    }
}

static void ev_io_read_cb(struct ev_loop *loop, ev_io *w, int revents)
{
    struct eco_socket *sock = container_of(w, struct eco_socket, rcv.io);

    ev_io_stop(loop, w);
    ev_timer_stop(loop, &sock->tmr);
    eco_resume(sock->eco->L, sock->rcv.co, 0);
}

static void ev_io_write_cb(struct ev_loop *loop, ev_io *w, int revents)
{
    struct eco_socket *sock = container_of(w, struct eco_socket, snd.io);

    ev_io_stop(loop, w);

    if (sock->flag.connecting)
        ev_timer_stop(loop, &sock->tmr);

    eco_resume(sock->eco->L, sock->snd.co, 0);
}

static int lua_push_sockaddr(lua_State *L, struct sockaddr *addr, socklen_t len)
{
    int family = addr->sa_family;

    lua_createtable(L, 0, 2);

    lua_pushinteger(L, family);
    lua_setfield(L, -2, "family");

    if (family == AF_NETLINK) {
        struct sockaddr_nl *nl = (struct sockaddr_nl *)addr;
        lua_pushinteger(L, nl->nl_pid);
        lua_setfield(L, -2, "pid");
    } if (family == AF_UNIX) {
        lua_pushlstring(L, ((struct sockaddr_un *)addr)->sun_path, len - 2);
        lua_setfield(L, -2, "path");
    } else if (family == AF_INET) {
        struct sockaddr_in *in = (struct sockaddr_in *)addr;
        char ip[INET_ADDRSTRLEN];

        lua_pushinteger(L, ntohs(in->sin_port));
        lua_setfield(L, -2, "port");

        lua_pushstring(L, inet_ntop(AF_INET, &in->sin_addr, ip, sizeof(ip)));
        lua_setfield(L, -2, "ipaddr");
    } else if (family == AF_INET6) {
        struct sockaddr_in6 *in6 = (struct sockaddr_in6 *)addr;
        char ip[INET6_ADDRSTRLEN];

        lua_pushinteger(L, ntohs(in6->sin6_port));
        lua_setfield(L, -2, "port");

        lua_pushstring(L, inet_ntop(AF_INET6, &in6->sin6_addr, ip, sizeof(ip)));
        lua_setfield(L, -2, "ipaddr");
    } else if (family == AF_PACKET) {
        struct sockaddr_ll *ll = (struct sockaddr_ll *)addr;
        char ifname[IF_NAMESIZE];

        lua_pushinteger(L, ll->sll_ifindex);
        lua_setfield(L, -2, "ifindex");

        lua_pushstring(L, if_indextoname(ll->sll_ifindex, ifname));
        lua_setfield(L, -2, "ifname");
    }

    return 1;
}

static int lua_args_to_sockaddr(struct eco_socket *sock, lua_State *L, struct sockaddr *a, int offset)
{
    socklen_t addrlen;
    const char *ip;
    size_t pathlen;
    union {
        struct sockaddr a;
        struct sockaddr_nl nl;
        struct sockaddr_un un;
        struct sockaddr_in in;
        struct sockaddr_in6 in6;
        struct sockaddr_ll ll;
    } addr = {
        .a.sa_family = sock->domain
    };

    switch (sock->domain) {
    case AF_INET:
        ip = lua_tostring(L, 2 + offset);

        if (ip && inet_pton(AF_INET, ip, &addr.in.sin_addr) != 1)
            luaL_argerror(L, 2 + offset, "not a valid IPv4 address");

        addr.in.sin_port = htons(luaL_checkinteger(L, 3 + offset));
        addrlen = sizeof(struct sockaddr_in);
        break;

    case AF_INET6:
        ip = lua_tostring(L, 2 + offset);

        if (ip && inet_pton(AF_INET6, ip, &addr.in6.sin6_addr) != 1)
            luaL_argerror(L, 2 + offset, "not a valid IPv6 address");\

        addr.in6.sin6_port = htons(luaL_checkinteger(L, 3 + offset));
        addrlen = sizeof(struct sockaddr_in6);
        break;

    case AF_UNIX:
        ip = luaL_checklstring(L, 2 + offset, &pathlen);

        if (pathlen >= sizeof(addr.un.sun_path))
            luaL_argerror(L, 2 + offset, "path too long");

        memcpy(addr.un.sun_path, ip, pathlen);
        addrlen = 2 + pathlen;
        break;

    case AF_NETLINK:
        addrlen = sizeof(struct sockaddr_nl);
        addr.nl.nl_groups = luaL_optinteger(L, 2 + offset, 0);
        addr.nl.nl_pid = luaL_optinteger(L, 3 + offset, 0);
        break;

    case AF_PACKET:
        luaL_checktype(L, 2 + offset, LUA_TTABLE);

        addrlen = sizeof(struct sockaddr_ll);

        lua_getfield(L, 2 + offset, "ifindex");
        if (!lua_isnil(L, -1))
            addr.ll.sll_ifindex = luaL_checkinteger(L, -1);
        lua_pop(L, 1);

        lua_getfield(L, 2 + offset, "ifname");
        if (!lua_isnil(L, -1)) {
            const char *ifname = luaL_checkstring(L, -1);
            addr.ll.sll_ifindex = if_nametoindex(ifname);
        }
        lua_pop(L, 1);
        break;

    default:
        return luaL_error(L, "invalid domain");
    }

    memcpy(a, &addr, addrlen);

    return addrlen;
}

static int eco_socket_init(lua_State *L, int fd, int domain, bool established)
{
    struct eco_socket *sock = lua_newuserdata(L, sizeof(struct eco_socket));

    memset(sock, 0, sizeof(struct eco_socket));

    luaL_getmetatable(L, ECO_SOCKET_MT);
    lua_setmetatable(L, -2);

    sock->eco = eco_get_context(L);
    sock->domain = domain;
    sock->flag.established = established;
    sock->fd = fd;

    ev_timer_init(&sock->tmr, ev_timer_cb, 0.0, 0);

    ev_io_init(&sock->rcv.io, ev_io_read_cb, fd, EV_READ);
    ev_io_init(&sock->snd.io, ev_io_write_cb, fd, EV_WRITE);

    return 1;
}

static int lua_bind(lua_State *L)
{
    struct eco_socket *sock = luaL_checkudata(L, 1, ECO_SOCKET_MT);
    uint8_t addr[sizeof(struct sockaddr_un)];
    socklen_t addrlen = lua_args_to_sockaddr(sock, L, (struct sockaddr *)addr, 0);

    if (bind(sock->fd, (struct sockaddr *)&addr, addrlen)) {
        lua_pushnil(L);
        lua_pushstring(L, strerror(errno));
        return 2;
    }

    lua_pushvalue(L, 1);
    return 1;
}

static int lua_listen(lua_State *L)
{
    struct eco_socket *sock = luaL_checkudata(L, 1, ECO_SOCKET_MT);
    int backlog = luaL_optinteger(L, 2, SOMAXCONN);

    if (listen(sock->fd, backlog)) {
        lua_pushnil(L);
        lua_pushstring(L, strerror(errno));
        return 2;
    }

    lua_pushvalue(L, 1);
    return 1;
}

static int lua_acceptk(lua_State *L, int status, lua_KContext ctx)
{
    struct eco_socket *sock = (struct eco_socket *)ctx;
    union {
        struct sockaddr_un un;
        struct sockaddr_in in;
        struct sockaddr_in6 in6;
    } addr = {};
    socklen_t addrlen = sizeof(addr);
    int fd;

    sock->rcv.co = NULL;

again:
    fd = accept4(sock->fd, (struct sockaddr *)&addr, &addrlen, SOCK_NONBLOCK | SOCK_CLOEXEC);
    if (fd < 0) {
        if (errno == EINTR)
            goto again;

        if (errno == EAGAIN) {
            sock->rcv.co = L;
            ev_io_start(sock->eco->loop, &sock->rcv.io);
            return lua_yieldk(L, 0, ctx, lua_acceptk);
        }

        lua_pushnil(L);
        lua_pushstring(L, strerror(errno));
        return 2;
    }

    eco_socket_init(L, fd, sock->domain, true);
    lua_push_sockaddr(L, (struct sockaddr *)&addr, addrlen);

    return 2;
}

static int lua_accept(lua_State *L)
{
    struct eco_socket *sock = luaL_checkudata(L, 1, ECO_SOCKET_MT);

    return lua_acceptk(L, 0, (lua_KContext)sock);
}

static int lua_connectk(lua_State *L, int status, lua_KContext ctx)
{
    struct eco_socket *sock = (struct eco_socket *)ctx;
    socklen_t len = sizeof(int);
    int narg = 1;
    int err = 0;

    sock->flag.connecting = false;
    sock->snd.co = NULL;

    if (sock->flag.overtime) {
        sock->flag.overtime = 0;
        lua_pushnil(L);
        lua_pushliteral(L, "timeout");
        return 2;
    }

    if (getsockopt(sock->fd, SOL_SOCKET, SO_ERROR, &err, &len) < 0)
        err = errno;

    if (err) {
        narg++;
        lua_pushnil(L);
        lua_pushstring(L, strerror(err));
    } else {
        lua_pushvalue(L, 1);
    }

    return narg;
}

static int lua_connect(lua_State *L)
{
    struct eco_socket *sock = luaL_checkudata(L, 1, ECO_SOCKET_MT);
    uint8_t addr[sizeof(struct sockaddr_un)];
    socklen_t addrlen = lua_args_to_sockaddr(sock, L, (struct sockaddr *)addr, 0);

again:
    if (connect(sock->fd, (struct sockaddr *)&addr, addrlen)) {
        if (errno == EINPROGRESS) {
            ev_timer_set(&sock->tmr, 5.0, 0);
            ev_timer_start(sock->eco->loop, &sock->tmr);

            ev_io_start(sock->eco->loop, &sock->snd.io);

            sock->flag.connecting = true;
            sock->snd.co = L;

            return lua_yieldk(L, 0, (lua_KContext)sock, lua_connectk);
        }

        if (errno == EINTR)
            goto again;

        lua_pushnil(L);
        lua_pushstring(L, strerror(errno));
        return 2;
    }

    lua_pushvalue(L, 1);
    return 1;
}

static int lua_recvk(lua_State *L, int status, lua_KContext ctx)
{
    struct eco_socket *sock = (struct eco_socket *)ctx;
    union {
        struct sockaddr_ll ll;
        struct sockaddr_nl nl;
        struct sockaddr_un un;
        struct sockaddr_in in;
        struct sockaddr_in6 in6;
    } addr = {};
    socklen_t addrlen = sizeof(addr);
    void *buf = sock->rcv.buf;
    size_t len = sock->rcv.len;
    bool from = sock->rcv.from;
    int fd = sock->fd;
    ssize_t ret;

    sock->rcv.co = NULL;

    if (sock->flag.overtime) {
        sock->flag.overtime = 0;
        free(buf);
        lua_pushnil(L);
        lua_pushliteral(L, "timeout");
        return 2;
    }

again:
    if (sock->rcv.from)
        ret = recvfrom(fd, buf, len, 0, (struct sockaddr *)&addr, &addrlen);
    else
        ret = recv(fd, buf, len, 0);
    if (ret < 0) {
        if (errno == EINTR)
            goto again;

        if (errno == EAGAIN) {
            sock->rcv.co = L;

            if (sock->rcv.timeout > 0) {
                ev_timer_set(&sock->tmr, sock->rcv.timeout, 0);
                ev_timer_start(sock->eco->loop, &sock->tmr);
            }

            ev_io_start(sock->eco->loop, &sock->rcv.io);
            return lua_yieldk(L, 0, ctx, lua_recvk);
        }

        free(buf);
        lua_pushnil(L);
        lua_pushstring(L, strerror(errno));
        return 2;
    }

    lua_pushlstring(L, buf, ret);
    free(buf);

    if (from && addrlen) {
        lua_push_sockaddr(L, (struct sockaddr *)&addr, addrlen);
        return 2;
    }

    return 1;
}

static int __lua_recv(lua_State *L, bool from)
{
    struct eco_socket *sock = luaL_checkudata(L, 1, ECO_SOCKET_MT);

    if (sock->rcv.co) {
        lua_pushnil(L);
        lua_pushliteral(L, "busy reading");
        return 2;
    }

    sock->rcv.len = luaL_checkinteger(L, 2);
    sock->rcv.timeout = lua_tonumber(L, 3);
    sock->rcv.from = from;

    sock->rcv.buf = malloc(sock->rcv.len);
    if (!sock->rcv.buf) {
        lua_pushnil(L);
        lua_pushstring(L, strerror(errno));
        return 2;
    }

    return lua_recvk(L, 0, (lua_KContext)sock);
}

static int lua_recv(lua_State *L)
{
    return __lua_recv(L, false);
}

static int lua_recvfrom(lua_State *L)
{
    return __lua_recv(L, true);
}

static inline int lua_init_snd(struct eco_socket *sock, lua_State *L)
{
    if (sock->fd < 0) {
        lua_pushnil(L);
        lua_pushliteral(L, "closed");
        return -1;
    }

    if (sock->snd.co) {
        lua_pushnil(L);
        lua_pushliteral(L, "busy");
        return -1;
    }

    sock->snd.data = luaL_checklstring(L, 2, &sock->snd.len);
    sock->snd.sent = 0;
    sock->snd.addrlen = 0;

    return 0;
}

static int lua_sendk(lua_State *L, int status, lua_KContext ctx)
{
    struct eco_socket *sock = (struct eco_socket *)ctx;
    socklen_t addrlen = sock->snd.addrlen;
    const void *data = sock->snd.data;
    size_t sent = sock->snd.sent;
    size_t len = sock->snd.len;
    int ret;

    sock->snd.co = NULL;

    if (sent == len) {
        lua_pushinteger(L, sent);
        return 1;
    }

    if (sock->fd < 0) {
        lua_pushnil(L);
        lua_pushliteral(L, "closed");
        return 2;
    }

    if (addrlen)
        ret = sendto(sock->fd, data, len - sent, 0, (struct sockaddr *)&sock->snd.addr, addrlen);
    else
        ret = send(sock->fd, data, len - sent, 0);
    if (ret < 0) {
        if (errno == EINTR || errno == EAGAIN)
            goto again;

        lua_pushnil(L);
        if (errno == EPIPE)
            lua_pushliteral(L, "closed");
        else
            lua_pushstring(L, strerror(errno));
        return 2;
    }

    sock->snd.sent += ret;
    sock->snd.data += ret;

again:
    sock->snd.co = L;
    ev_io_start(sock->eco->loop, &sock->snd.io);
    return lua_yieldk(L, 0, ctx, lua_sendk);
}

static int lua_send(lua_State *L)
{
    struct eco_socket *sock = luaL_checkudata(L, 1, ECO_SOCKET_MT);

    if (lua_init_snd(sock, L))
        return 2;

    return lua_sendk(L, 0, (lua_KContext)sock);
}

static int lua_sendto(lua_State *L)
{
    struct eco_socket *sock = luaL_checkudata(L, 1, ECO_SOCKET_MT);

    if (lua_init_snd(sock, L))
        return 2;

    sock->snd.addrlen = lua_args_to_sockaddr(sock, L, (struct sockaddr *)sock->snd.addr, 1);

    return lua_sendk(L, 0, (lua_KContext)sock);
}

static int lua_sendfilek(lua_State *L, int status, lua_KContext ctx)
{
    struct eco_socket *sock = (struct eco_socket *)ctx;
    int fd = sock->snd.fd;
    int len = sock->snd.len;
    size_t sent = sock->snd.sent;
    off_t offset = sock->snd.offset;
    int ret;

    sock->snd.co = NULL;

    if (sent == len) {
        close(sock->snd.fd);
        lua_pushinteger(L, sent);
        return 1;
    }

    if (sock->fd < 0) {
        lua_pushnil(L);
        lua_pushliteral(L, "closed");
        return 2;
    }

    if (offset < 0)
        ret = sendfile(sock->fd, fd, NULL, len - sent);
    else
        ret = sendfile(sock->fd, fd, &offset, len - sent);
    if (ret < 0) {
        if (errno == EINTR || errno == EAGAIN)
            goto again;

        close(sock->snd.fd);
        lua_pushnil(L);
        if (errno == EPIPE)
            lua_pushliteral(L, "closed");
        else
            lua_pushstring(L, strerror(errno));
        return 2;
    }

    sock->snd.sent += ret;
    sock->snd.offset = offset;

    if (ret == 0)
        sock->snd.len = sock->snd.sent;

again:
    sock->snd.co = L;
    ev_io_start(sock->eco->loop, &sock->snd.io);
    return lua_yieldk(L, 0, ctx, lua_sendfilek);
}

static int lua_sendfile(lua_State *L)
{
    struct eco_socket *sock = luaL_checkudata(L, 1, ECO_SOCKET_MT);
    const char *path;
    int fd;

    if (sock->fd < 0) {
        lua_pushnil(L);
        lua_pushliteral(L, "closed");
        return 2;
    }

    if (sock->snd.co) {
        lua_pushnil(L);
        lua_pushliteral(L, "busy");
        return 2;
    }

    path = luaL_checkstring(L, 2);

    fd = open(path, O_RDONLY);
    if (fd < 0) {
        lua_pushnil(L);
        lua_pushstring(L, strerror(errno));
        return 2;
    }

    sock->snd.sent = 0;
    sock->snd.fd = fd;
    sock->snd.len = luaL_checkinteger(L, 3);
    sock->snd.offset = luaL_optinteger(L, 4, -1);

    return lua_sendfilek(L, 0, (lua_KContext)sock);
}

static int lua_getsockname(lua_State *L)
{
    struct eco_socket *sock = luaL_checkudata(L, 1, ECO_SOCKET_MT);
    union {
        struct sockaddr_un un;
        struct sockaddr_in in;
        struct sockaddr_in6 in6;
    } addr = {};
    socklen_t addrlen = sizeof(addr);

    if (getsockname(sock->fd, (struct sockaddr *)&addr, &addrlen)) {
        lua_pushnil(L);
        lua_pushstring(L, strerror(errno));
        return 2;
    }

    return lua_push_sockaddr(L, (struct sockaddr *)&addr, addrlen);
}

static int lua_getpeername(lua_State *L)
{
    struct eco_socket *sock = luaL_checkudata(L, 1, ECO_SOCKET_MT);
    uint8_t addr[sizeof(struct sockaddr_un)];
    socklen_t addrlen = sizeof(addr);

    if (getpeername(sock->fd, (struct sockaddr *)&addr, &addrlen)) {
        lua_pushnil(L);
        lua_pushstring(L, strerror(errno));
        return 2;
    }

    return lua_push_sockaddr(L, (struct sockaddr *)&addr, addrlen);
}

static int sockopt_set(struct eco_socket *sock, lua_State *L,
                    struct sock_opt *o, void *val, int len)
{
    if (setsockopt(sock->fd, o->level, o->opt, val, len) < 0) {
        lua_pushnil(L);
        lua_pushstring(L, strerror(errno));
        return 2;
    }

    lua_pushboolean(L, true);

    return 1;
}

static int sockopt_set_boolean(struct eco_socket *sock, lua_State *L, struct sock_opt *o)
{
    int val;

    luaL_checktype(L, 3, LUA_TBOOLEAN);

    val = lua_toboolean(L, 3);

    return sockopt_set(sock, L, o, &val, sizeof(val));
}

static int sockopt_set_int(struct eco_socket *sock, lua_State *L, struct sock_opt *o)
{
    int val = luaL_checkinteger(L, 3);

    return sockopt_set(sock, L, o, &val, sizeof(val));
}

static int sockopt_set_bindtodevice(struct eco_socket *sock, lua_State *L, struct sock_opt *o)
{
    const char *ifname = luaL_checkstring(L, 3);
    struct ifreq ifr = {};

    if (strlen(ifname) >= IFNAMSIZ)
        luaL_argerror(L, 3, "ifname too long");

    strcpy(ifr.ifr_name, ifname);

    return sockopt_set(sock, L, o, &ifr, sizeof(ifr));
}

static int sockopt_set_ip_membership(struct eco_socket *sock, lua_State *L, struct sock_opt *o)
{
    struct ip_mreq mreq = {};
    const char *multiaddr;

    luaL_checktype(L, 3, LUA_TTABLE);

    lua_getfield(L, 3, "multiaddr");

    multiaddr = lua_tostring(L, -1);

    if (!multiaddr || inet_pton(AF_INET, multiaddr, &mreq.imr_multiaddr) != 1)
        luaL_argerror(L, 3, "multiaddr: not a valid IP address");

    lua_getfield(L, 3, "interface");

    if (lua_isstring(L, -1)) {
        const char *interface = lua_tostring(L, -1);
        if (inet_pton(AF_INET, interface, &mreq.imr_interface) != 1)
            luaL_argerror(L, 3, "interface: not a valid IP address");
    }

    return sockopt_set(sock, L, o, &mreq, sizeof(mreq));
}

static int sockopt_set_ipv6_membership(struct eco_socket *sock, lua_State *L, struct sock_opt *o)
{
    struct ipv6_mreq mreq;
    const char *multiaddr;

    luaL_checktype(L, 3, LUA_TTABLE);

    lua_getfield(L, 3, "multiaddr");

    multiaddr = lua_tostring(L, -1);

    if (!multiaddr || inet_pton(AF_INET6, multiaddr, &mreq.ipv6mr_multiaddr) != 1)
        luaL_argerror(L, 3, "multiaddr: not a valid IPv6 address");

    lua_getfield(L, 3, "interface");

    mreq.ipv6mr_interface = luaL_optinteger(L, -1, 0);

    return sockopt_set(sock, L, o, &mreq, sizeof(mreq));
}

static int sockopt_set_packet_membership(struct eco_socket *sock, lua_State *L, struct sock_opt *o)
{
    struct packet_mreq mreq = {};

    luaL_checktype(L, 3, LUA_TTABLE);

    lua_getfield(L, 3, "ifname");
    if (!lua_isnil(L, -1)) {
        const char *ifname = luaL_checkstring(L, -1);
        unsigned int ifindex = if_nametoindex(ifname);
        if (!ifindex) {
            lua_pushnil(L);
            lua_pushfstring(L, "No interface found with given name '%s'", ifname);
            return 2;
        }
        mreq.mr_ifindex = ifindex;
    }
    lua_pop(L, 1);

    if (mreq.mr_ifindex == 0) {
        lua_getfield(L, 3, "ifindex");
        if (!lua_isnil(L, -1))
            mreq.mr_ifindex = luaL_checkinteger(L, -1);
        lua_pop(L, 1);
    }

    lua_getfield(L, 3, "type");
    mreq.mr_type = luaL_checkinteger(L, -1);
    lua_pop(L, 1);

    return sockopt_set(sock, L, o, &mreq, sizeof(mreq));
}

static struct sock_opt optsets[] = {
    {"reuseaddr", SOL_SOCKET, SO_REUSEADDR, sockopt_set_boolean},
    {"reuseport", SOL_SOCKET, SO_REUSEPORT, sockopt_set_boolean},
    {"keepalive", SOL_SOCKET, SO_KEEPALIVE, sockopt_set_boolean},
    {"sndbuf", SOL_SOCKET, SO_SNDBUF, sockopt_set_int},
    {"rcvbuf", SOL_SOCKET, SO_RCVBUF, sockopt_set_int},
    {"mark", SOL_SOCKET, SO_MARK, sockopt_set_int},
    {"bindtodevice", SOL_SOCKET, SO_BINDTODEVICE, sockopt_set_bindtodevice},
    {"tcp_keepidle", SOL_TCP, TCP_KEEPIDLE, sockopt_set_int},
    {"tcp_keepintvl", SOL_TCP, TCP_KEEPINTVL, sockopt_set_int},
    {"tcp_keepcnt", SOL_TCP, TCP_KEEPCNT, sockopt_set_int},
    {"tcp_fastopen", SOL_TCP, TCP_FASTOPEN, sockopt_set_int},
    {"tcp_nodelay", SOL_TCP, TCP_NODELAY, sockopt_set_boolean},
    {"ip_add_membership", SOL_IP, IP_ADD_MEMBERSHIP, sockopt_set_ip_membership},
    {"ip_drop_membership", SOL_IP, IP_DROP_MEMBERSHIP, sockopt_set_ip_membership},
    {"ipv6_v6only", SOL_IPV6, IPV6_V6ONLY, sockopt_set_boolean},
    {"ipv6_add_membership", SOL_IPV6, IPV6_ADD_MEMBERSHIP, sockopt_set_ipv6_membership},
    {"ipv6_drop_membership", SOL_IPV6, IPV6_DROP_MEMBERSHIP, sockopt_set_ipv6_membership},
    {"netlink_add_membership", SOL_NETLINK, NETLINK_ADD_MEMBERSHIP, sockopt_set_int},
    {"netlink_drop_membership", SOL_NETLINK, NETLINK_DROP_MEMBERSHIP, sockopt_set_int},
    {"packet_add_membership", SOL_PACKET, PACKET_ADD_MEMBERSHIP, sockopt_set_packet_membership},
    {"packet_drop_membership", SOL_PACKET, PACKET_DROP_MEMBERSHIP, sockopt_set_packet_membership},
    {}
};

static int lua_setoption(lua_State *L)
{
    struct eco_socket *sock = luaL_checkudata(L, 1, ECO_SOCKET_MT);
    const char *name = luaL_checkstring(L, 2);
    struct sock_opt *o = optsets;

    while (o->name && strcmp(name, o->name))
        o++;

    if (!o->func) {
        char msg[60];
        sprintf(msg, "unsupported option '%.35s'", name);
        luaL_argerror(L, 2, msg);
    }

    return o->func(sock, L, o);
}

static int lua_getfd(lua_State *L)
{
    struct eco_socket *sock = luaL_checkudata(L, 1, ECO_SOCKET_MT);

    lua_pushinteger(L, sock->fd);

    return 1;
}

static int lua_closed(lua_State *L)
{
    struct eco_socket *sock = luaL_checkudata(L, 1, ECO_SOCKET_MT);

    lua_pushboolean(L, sock->fd < 0);

    return 1;
}

static int lua_sock_close(lua_State *L)
{
    struct eco_socket *sock = luaL_checkudata(L, 1, ECO_SOCKET_MT);
    struct ev_loop *loop = sock->eco->loop;

    if (sock->fd < 0)
        return 0;

    if (sock->domain == AF_UNIX && !sock->flag.established) {
        struct sockaddr_un un;
        socklen_t addrlen = sizeof(un);

        if (!getsockname(sock->fd, (struct sockaddr *)&un, &addrlen))
            unlink(un.sun_path);
    }

    ev_timer_stop(loop, &sock->tmr);
    ev_io_stop(loop, &sock->rcv.io);
    ev_io_stop(loop, &sock->snd.io);

    close(sock->fd);

    sock->fd = -1;

    return 0;
}

static const luaL_Reg methods[] = {
    {"bind", lua_bind},
    {"listen", lua_listen},
    {"accept", lua_accept},
    {"connect", lua_connect},
    {"recv", lua_recv},
    {"recvfrom", lua_recvfrom},
    {"send", lua_send},
    {"sendto", lua_sendto},
    {"sendfile", lua_sendfile},
    {"getsockname", lua_getsockname},
    {"getpeername", lua_getpeername},
    {"setoption", lua_setoption},
    {"getfd", lua_getfd},
    {"closed", lua_closed},
    {"close", lua_sock_close},
    {"__gc", lua_sock_close},
    {NULL, NULL}
};

static int lua_socket(lua_State *L)
{
    int domain = luaL_checkinteger(L, 1);
    int type = luaL_checkinteger(L, 2);
    int protocol = lua_tointeger(L, 3);
    int fd;

    fd = socket(domain, type | SOCK_NONBLOCK | SOCK_CLOEXEC, protocol);
    if (fd < 0) {
        lua_pushnil(L);
        lua_pushstring(L, strerror(errno));
        return 2;
    }

    return eco_socket_init(L, fd, domain, 0);
}

static int lua_is_ipv4_address(lua_State *L)
{
    const char *ip = luaL_checkstring(L, 1);
    struct in_addr addr;

    lua_pushboolean(L, inet_pton(AF_INET, ip, &addr) == 1);
    return 1;
}

static int lua_is_ipv6_address(lua_State *L)
{
    const char *ip = luaL_checkstring(L, 1);
    struct in6_addr addr;

    lua_pushboolean(L, inet_pton(AF_INET6, ip, &addr) == 1);
    return 1;
}

static int lua_inet_aton(lua_State *L)
{
    const char *src = luaL_checkstring(L, 1);
    struct in_addr in = {};

    inet_aton(src, &in);
    lua_pushinteger(L, in.s_addr);

    return 1;
}

static int lua_inet_ntoa(lua_State *L)
{
    struct in_addr in;

    in.s_addr = (uint32_t)luaL_checknumber(L, 1);
    lua_pushstring(L, inet_ntoa(in));

    return 1;
}

static int lua_inet_ntop(lua_State *L)
{
    int family = luaL_checkinteger(L, 1);
    const void *src = luaL_checkstring(L, 2);
    char dst[INET6_ADDRSTRLEN];

    if (inet_ntop(family, src, dst, sizeof(dst)))
        lua_pushstring(L, dst);
    else
        lua_pushnil(L);

    return 1;
}

static int lua_inet_pton(lua_State *L)
{
    int family = luaL_checkinteger(L, 1);
    const void *src = luaL_checkstring(L, 2);
    char dst[sizeof(struct in6_addr)];

    if (inet_pton(family, src, dst))
        lua_pushlstring(L, dst, sizeof(dst));
    else
        lua_pushnil(L);

    return 1;
}

static int lua_if_nametoindex(lua_State *L)
{
    const char *ifname = luaL_checkstring(L, 1);
    unsigned int ifidx = if_nametoindex(ifname);

    if (ifidx == 0)
        lua_pushnil(L);
    else
        lua_pushinteger(L, ifidx);

    return 1;
}

static int lua_if_indextoname(lua_State *L)
{
    int index = luaL_checkinteger(L, 1);
    char ifname[IF_NAMESIZE] = "";

    if_indextoname(index, ifname);
    lua_pushstring(L, ifname);

    return 1;
}

static int lua_htonl(lua_State *L)
{
    uint32_t n = luaL_checkinteger(L, 1);
    lua_pushinteger(L, htonl(n));
    return 1;
}

static int lua_htons(lua_State *L)
{
    uint16_t n = luaL_checkinteger(L, 1);
    lua_pushinteger(L, htons(n));
    return 1;
}

static int lua_ntohl(lua_State *L)
{
    uint32_t n = luaL_checkinteger(L, 1);
    lua_pushinteger(L, ntohl(n));
    return 1;
}

static int lua_ntohs(lua_State *L)
{
    uint16_t n = luaL_checkinteger(L, 1);
    lua_pushinteger(L, ntohs(n));
    return 1;
}

static const luaL_Reg funcs[] = {
    {"socket", lua_socket},
    {"is_ipv4_address", lua_is_ipv4_address},
    {"is_ipv6_address", lua_is_ipv6_address},
    {"inet_aton", lua_inet_aton},
    {"inet_ntoa", lua_inet_ntoa},
    {"inet_ntop", lua_inet_ntop},
    {"inet_pton", lua_inet_pton},
    {"if_nametoindex", lua_if_nametoindex},
    {"if_indextoname", lua_if_indextoname},
    {"htonl", lua_htonl},
    {"htons", lua_htons},
    {"ntohl", lua_ntohl},
    {"ntohs", lua_ntohs},
    {NULL, NULL}
};

int luaopen_eco_core_socket(lua_State *L)
{
    eco_new_metatable(L, ECO_SOCKET_MT, methods);

    luaL_newlib(L, funcs);

    lua_add_constant(L, "AF_UNSPEC", AF_UNSPEC);
    lua_add_constant(L, "AF_INET", AF_INET);
    lua_add_constant(L, "AF_INET6", AF_INET6);
    lua_add_constant(L, "AF_UNIX", AF_UNIX);
    lua_add_constant(L, "AF_PACKET", AF_PACKET);
    lua_add_constant(L, "AF_NETLINK", AF_NETLINK);

    lua_add_constant(L, "SOCK_DGRAM", SOCK_DGRAM);
    lua_add_constant(L, "SOCK_STREAM", SOCK_STREAM);
    lua_add_constant(L, "SOCK_RAW", SOCK_RAW);

    lua_add_constant(L, "IPPROTO_ICMP", IPPROTO_ICMP);
    lua_add_constant(L, "IPPROTO_ICMPV6", IPPROTO_ICMPV6);

    lua_add_constant(L, "IPPROTO_TCP", IPPROTO_TCP);
    lua_add_constant(L, "IPPROTO_UDP", IPPROTO_UDP);

    lua_add_constant(L, "ETH_P_IP", ETH_P_IP);
    lua_add_constant(L, "ETH_P_ARP", ETH_P_ARP);
    lua_add_constant(L, "ETH_P_8021Q", ETH_P_8021Q);
    lua_add_constant(L, "ETH_P_PPP_DISC", ETH_P_PPP_DISC);
    lua_add_constant(L, "ETH_P_PPP_SES", ETH_P_PPP_SES);
    lua_add_constant(L, "ETH_P_IPV6", ETH_P_IPV6);
    lua_add_constant(L, "ETH_P_ALL", ETH_P_ALL);

    lua_add_constant(L, "ARPHRD_ETHER", ARPHRD_ETHER);

    lua_add_constant(L, "ARPOP_REQUEST", ARPOP_REQUEST);
    lua_add_constant(L, "ARPOP_REPLY", ARPOP_REPLY);

    lua_add_constant(L, "PACKET_MR_PROMISC", PACKET_MR_PROMISC);

    lua_add_constant(L, "ICMP_ECHOREPLY", ICMP_ECHOREPLY);
    lua_add_constant(L, "ICMP_ECHO", ICMP_ECHO);
    lua_add_constant(L, "ICMP_REDIRECT", ICMP_REDIRECT);

    lua_add_constant(L, "ICMPV6_ECHO_REQUEST", ICMPV6_ECHO_REQUEST);
    lua_add_constant(L, "ICMPV6_ECHO_REPLY", ICMPV6_ECHO_REPLY);

    return 1;
}
