/* SPDX-License-Identifier: MIT */
/*
 * Author: Jianhui Zhao <zhaojh329@gmail.com>
 */

#include <netinet/tcp.h>
#include <sys/socket.h>
#include <arpa/inet.h>
#include <linux/if.h>
#include <stdlib.h>
#include <sys/un.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>

#include "eco.h"

struct sock_opt {
  const char *name;
  int (*func)(lua_State *L, int fd);
};

static void push_socket_addr(lua_State *L, struct sockaddr *addr)
{
    int family = addr->sa_family;
    char ip[INET6_ADDRSTRLEN];

    lua_createtable(L, 0, 2);

    lua_pushinteger(L, family);
    lua_setfield(L, -2, "family");

    if (family == AF_UNIX) {
        lua_pushstring(L, ((struct sockaddr_un *)addr)->sun_path);
        lua_setfield(L, -2, "path");
    } else if (family == AF_INET) {
        struct sockaddr_in *in = (struct sockaddr_in *)addr;

        lua_pushinteger(L, ntohs(in->sin_port));
        lua_setfield(L, -2, "port");

        lua_pushstring(L, inet_ntop(AF_INET, &in->sin_addr, ip, sizeof(ip)));
        lua_setfield(L, -2, "ipaddr");
    } else if (family == AF_INET6) {
        struct sockaddr_in6 *in6 = (struct sockaddr_in6 *)addr;

        lua_pushinteger(L, ntohs(in6->sin6_port));
        lua_setfield(L, -2, "port");

        lua_pushstring(L, inet_ntop(AF_INET6, &in6->sin6_addr, ip, sizeof(ip)));
        lua_setfield(L, -2, "ipaddr");
    }
}

static int eco_socket_socket(lua_State *L)
{
    int domain = luaL_checkinteger(L, 1);
    int type = luaL_checkinteger(L, 2);
    int protocol = lua_tointeger(L, 3);
    int fd;

    fd = socket(domain, type | SOCK_NONBLOCK | SOCK_CLOEXEC, protocol);
    if (fd < 0) {
        lua_pushnil(L);
        lua_pushinteger(L, errno);
        return 2;
    }

    lua_pushinteger(L, fd);
    return 1;
}

static int eco_socket_bind_common(lua_State *L, int fd, struct sockaddr *addr, socklen_t addrlen)
{
    if (bind(fd, addr, addrlen)) {
        lua_pushboolean(L, false);
        lua_pushinteger(L, errno);
        return 2;
    }

    lua_pushboolean(L, true);
    return 1;
}

static int eco_socket_bind(lua_State *L)
{
    int fd = luaL_checkinteger(L, 1);
    const char *ip = lua_tostring(L, 2);
    int port = luaL_checkinteger(L, 3);
    struct sockaddr_in addr = {
        .sin_family = AF_INET,
        .sin_port = htons(port)
    };

    if (ip && inet_pton(AF_INET, ip, &addr.sin_addr) != 1)
        luaL_argerror(L, 2, "not a valid IPv4 address");

    return eco_socket_bind_common(L, fd, (struct sockaddr *)&addr, sizeof(struct sockaddr_in));
}

static int eco_socket_bind6(lua_State *L)
{
    int fd = luaL_checkinteger(L, 1);
    const char *ip = lua_tostring(L, 2);
    int port = luaL_checkinteger(L, 3);
    struct sockaddr_in6 addr = {
        .sin6_family = AF_INET6,
        .sin6_port = htons(port)
    };

    if (ip && inet_pton(AF_INET6, ip, &addr.sin6_addr) != 1)
        luaL_argerror(L, 2, "not a valid IPv6 address");

    return eco_socket_bind_common(L, fd, (struct sockaddr *)&addr, sizeof(struct sockaddr_in6));
}

static int eco_socket_bind_unix(lua_State *L)
{
    int fd = luaL_checkinteger(L, 1);
    const char *path = luaL_checkstring(L, 2);
    struct sockaddr_un addr = {
        .sun_family = AF_UNIX
    };

    if (strlen(path) >= sizeof(addr.sun_path))
        luaL_argerror(L, 2, "path too long");

    strcpy(addr.sun_path, path);

    return eco_socket_bind_common(L, fd, (struct sockaddr *)&addr, SUN_LEN(&addr));
}

static int eco_socket_listen(lua_State *L)
{
    int fd = luaL_checkinteger(L, 1);
    int backlog = luaL_optinteger(L, 2, SOMAXCONN);

    if (listen(fd, backlog)) {
        lua_pushboolean(L, false);
        lua_pushinteger(L, errno);
        return 2;
    }

    lua_pushboolean(L, true);
    return 1;
}

static int eco_socket_accept(lua_State *L)
{
    int lfd = luaL_checkinteger(L, 1);
    union {
        struct sockaddr_un un;
        struct sockaddr_in in;
        struct sockaddr_in6 in6;
    } addr = {};
    socklen_t addrlen = sizeof(addr);
    int fd;

again:
    fd = accept4(lfd, (struct sockaddr *)&addr, &addrlen, SOCK_NONBLOCK | SOCK_CLOEXEC);
    if (fd < 0) {
        if (errno == EINTR)
            goto again;
        lua_pushnil(L);
        lua_pushinteger(L, errno);
        return 2;
    }

    lua_pushinteger(L, fd);

    push_socket_addr(L, (struct sockaddr *)&addr);

    return 2;
}

static int eco_socket_connect_common(lua_State *L, int fd, struct sockaddr *addr, socklen_t addrlen)
{
    if (connect(fd, addr, addrlen) < 0) {
        lua_pushboolean(L, false);
        lua_pushinteger(L, errno);
        return 2;
    }

    lua_pushboolean(L, true);
    return 1;
}

static int eco_socket_connect(lua_State *L)
{
    int fd = luaL_checkinteger(L, 1);
    const char *ip = luaL_checkstring(L, 2);
    int port = luaL_checkinteger(L, 3);
    struct sockaddr_in addr = {
        .sin_family = AF_INET,
        .sin_port = htons(port)
    };

    if (inet_pton(AF_INET, ip, &addr.sin_addr) != 1)
        luaL_argerror(L, 2, "not a valid IPv4 address");

    return eco_socket_connect_common(L, fd, (struct sockaddr *)&addr, sizeof(struct sockaddr_in));
}

static int eco_socket_connect6(lua_State *L)
{
    int fd = luaL_checkinteger(L, 1);
    const char *ip = luaL_checkstring(L, 2);
    int port = luaL_checkinteger(L, 3);
    struct sockaddr_in6 addr = {
        .sin6_family = AF_INET6,
        .sin6_port = htons(port)
    };

    if (inet_pton(AF_INET6, ip, &addr.sin6_addr) != 1)
        luaL_argerror(L, 2, "not a valid IPv6 address");

    return eco_socket_connect_common(L, fd, (struct sockaddr *)&addr, sizeof(struct sockaddr_in6));
}

static int eco_socket_connect_unix(lua_State *L)
{
    int fd = luaL_checkinteger(L, 1);
    const char *path = luaL_checkstring(L, 2);
    struct sockaddr_un addr = {
        .sun_family = AF_UNIX
    };

    if (strlen(path) >= sizeof(addr.sun_path))
        luaL_argerror(L, 2, "path too long");

    strcpy(addr.sun_path, path);

    return eco_socket_connect_common(L, fd, (struct sockaddr *)&addr, SUN_LEN(&addr));
}

static int eco_socket_send(lua_State *L)
{
    int fd = luaL_checkinteger(L, 1);
    size_t len;
    const char *data = luaL_checklstring(L, 2, &len);
    int flags = luaL_optinteger(L, 3, 0);
    int ret;

again:
    ret = send(fd, data, len, flags);
    if (ret < 0) {
        if (errno == EINTR)
            goto again;
        lua_pushnil(L);
        lua_pushstring(L, strerror(errno));
        return 2;
    }

    lua_pushnumber(L, ret);
    return 1;
}

static int eco_socket_recv(lua_State *L)
{
    int fd = luaL_checkinteger(L, 1);
    size_t n = luaL_checkinteger(L, 2);
    int flags = luaL_optinteger(L, 3, 0);
    ssize_t ret;
    char *buf;

    if (n < 1)
        luaL_argerror(L, 2, "must be greater than 0");

    buf = malloc(n);
    if (!buf) {
        lua_pushnil(L);
        lua_pushstring(L, strerror(errno));
        return 2;
    }

again:
    ret = recv(fd, buf, n, flags);
    if (unlikely(ret < 0)) {
        if (errno == EINTR)
            goto again;
        free(buf);
        lua_pushnil(L);
        lua_pushstring(L, strerror(errno));
        return 2;
    }

    lua_pushlstring(L, buf, ret);
    free(buf);

    return 1;
}

static int eco_socket_sendto_common(lua_State *L, int fd, const void *data, size_t len,
    struct sockaddr *addr, socklen_t addrlen, int flags)
{
    int ret;

again:
    ret = sendto(fd, data, len, flags, addr, addrlen);
    if (ret < 0) {
        if (errno == EINTR)
            goto again;
        lua_pushnil(L);
        lua_pushstring(L, strerror(errno));
        return 2;
    }

    lua_pushnumber(L, ret);
    return 1;
}

static int eco_socket_sendto(lua_State *L)
{
    int fd = luaL_checkinteger(L, 1);
    size_t len;
    const char *data = luaL_checklstring(L, 2, &len);
    const char *ip = luaL_checkstring(L, 3);
    int port = luaL_checkinteger(L, 4);
    int flags = luaL_optinteger(L, 5, 0);
    struct sockaddr_in addr = {
        .sin_family = AF_INET,
        .sin_port = htons(port)
    };

    if (inet_pton(AF_INET, ip, &addr.sin_addr) != 1)
        luaL_argerror(L, 2, "not a valid IPv4 address");

    return eco_socket_sendto_common(L, fd, data, len, (struct sockaddr *)&addr, sizeof(struct sockaddr_in), flags);
}

static int eco_socket_sendto6(lua_State *L)
{
    int fd = luaL_checkinteger(L, 1);
    size_t len;
    const char *data = luaL_checklstring(L, 2, &len);
    const char *ip = luaL_checkstring(L, 3);
    int port = luaL_checkinteger(L, 4);
    int flags = luaL_optinteger(L, 5, 0);
    struct sockaddr_in6 addr = {
        .sin6_family = AF_INET6,
        .sin6_port = htons(port)
    };

    if (inet_pton(AF_INET6, ip, &addr.sin6_addr) != 1)
        luaL_argerror(L, 2, "not a valid IPv6 address");

    return eco_socket_sendto_common(L, fd, data, len, (struct sockaddr *)&addr, sizeof(struct sockaddr_in6), flags);
}

static int eco_socket_sendto_unix(lua_State *L)
{
    int fd = luaL_checkinteger(L, 1);
    size_t len;
    const char *data = luaL_checklstring(L, 2, &len);
    const char *path = luaL_checkstring(L, 3);
    int flags = luaL_optinteger(L, 4, 0);
    struct sockaddr_un addr = {
        .sun_family = AF_UNIX
    };

    if (strlen(path) >= sizeof(addr.sun_path))
        luaL_argerror(L, 2, "path too long");

    strcpy(addr.sun_path, path);

    return eco_socket_sendto_common(L, fd, data, len, (struct sockaddr *)&addr, SUN_LEN(&addr), flags);
}

static int eco_socket_recvfrom(lua_State *L)
{
    int fd = luaL_checkinteger(L, 1);
    size_t n = luaL_checkinteger(L, 2);
    int flags = luaL_optinteger(L, 3, 0);
    union {
        struct sockaddr_un un;
        struct sockaddr_in in;
        struct sockaddr_in6 in6;
    } addr = {};
    socklen_t addrlen = sizeof(addr);
    ssize_t ret;
    char *buf;

    if (n < 1)
        luaL_argerror(L, 2, "must be greater than 0");

    buf = malloc(n);
    if (!buf) {
        lua_pushnil(L);
        lua_pushstring(L, strerror(errno));
        return 2;
    }

again:
    ret = recvfrom(fd, buf, n, flags, (struct sockaddr *)&addr, &addrlen);
    if (ret < 0) {
        if (errno == EINTR)
            goto again;
        free(buf);
        lua_pushnil(L);
        lua_pushstring(L, strerror(errno));
        return 2;
    }

    lua_pushlstring(L, buf, ret);
    free(buf);

    push_socket_addr(L, (struct sockaddr *)&addr);

    return 2;
}

static int eco_socket_getsockname(lua_State *L)
{
    int fd = luaL_checkinteger(L, 1);
    union {
        struct sockaddr_un un;
        struct sockaddr_in in;
        struct sockaddr_in6 in6;
    } addr = {};
    socklen_t addrlen = sizeof(addr);

    if (getsockname(fd, (struct sockaddr *)&addr, &addrlen)) {
        lua_pushnil(L);
        lua_pushstring(L, strerror(errno));
        return 2;
    }

    push_socket_addr(L, (struct sockaddr *)&addr);

    return 1;
}

static int eco_socket_getpeername(lua_State *L)
{
    int fd = luaL_checkinteger(L, 1);
    union {
        struct sockaddr_un un;
        struct sockaddr_in in;
        struct sockaddr_in6 in6;
    } addr = {};
    socklen_t addrlen = sizeof(addr);

    if (getpeername(fd, (struct sockaddr *)&addr, &addrlen)) {
        lua_pushnil(L);
        lua_pushstring(L, strerror(errno));
        return 2;
    }

    push_socket_addr(L, (struct sockaddr *)&addr);

    return 1;
}

static int opt_getboolean(lua_State *L, int fd, int level, int name)
{
    socklen_t len = sizeof(int);
    int val = 0;

    if (getsockopt(fd, level, name, &val, &len) < 0) {
        lua_pushnil(L);
        lua_pushstring(L, strerror(errno));
        return 2;
    }

    lua_pushboolean(L, val);
    return 1;
}

static int opt_get_reuseaddr(lua_State *L, int fd)
{
    return opt_getboolean(L, fd, SOL_SOCKET, SO_REUSEADDR);
}

static int opt_get_error(lua_State *L, int fd)
{
    socklen_t len = sizeof(int);
    int val = 0;

    if (getsockopt(fd, SOL_SOCKET, SO_ERROR, &val, &len) < 0)
        val = errno;

    lua_pushinteger(L, val);

    return 1;
}

static struct sock_opt optget[] = {
    {"reuseaddr", opt_get_reuseaddr},
    {"error", opt_get_error},
    {NULL, NULL}
};

static int eco_socket_getoption(lua_State *L)
{
    int fd = luaL_checkinteger(L, 1);
    const char *name = luaL_checkstring(L, 2);
    struct sock_opt *o = optget;

    while (o->name && strcmp(name, o->name))
        o++;

    if (!o->func) {
        char msg[60];
        sprintf(msg, "unsupported option '%.35s'", name);
        luaL_argerror(L, 2, msg);
    }

    return o->func(L, fd);
}

static int opt_set(lua_State *L, int fd, int level, int name, void *val, int len)
{
    if (setsockopt(fd, level, name, val, len) < 0) {
        lua_pushboolean(L, false);
        lua_pushstring(L, strerror(errno));
        return 2;
    }

    lua_pushboolean(L, true);
    return 1;
}

static int opt_setboolean(lua_State *L, int fd, int level, int name)
{
    int val;

    luaL_checktype(L, 3, LUA_TBOOLEAN);

    val = lua_toboolean(L, 3);

    return opt_set(L, fd, level, name, &val, sizeof(val));
}

static int opt_setint(lua_State *L, int fd, int level, int name)
{
    int val = luaL_checkinteger(L, 3);
    return opt_set(L, fd, level, name, &val, sizeof(val));
}

static int opt_set_reuseaddr(lua_State *L, int fd)
{
    return opt_setboolean(L, fd, SOL_SOCKET, SO_REUSEADDR);
}

static int opt_set_reuseport(lua_State *L, int fd)
{
    return opt_setboolean(L, fd, SOL_SOCKET, SO_REUSEPORT);
}

static int opt_set_keepalive(lua_State *L, int fd)
{
    return opt_setboolean(L, fd, SOL_SOCKET, SO_KEEPALIVE);
}

static int opt_set_tcp_keepidle(lua_State *L, int fd)
{
    return opt_setint(L, fd, SOL_TCP, TCP_KEEPIDLE);
}

static int opt_set_tcp_keepintvl(lua_State *L, int fd)
{
    return opt_setint(L, fd, SOL_TCP, TCP_KEEPINTVL);
}

static int opt_set_tcp_keepcnt(lua_State *L, int fd)
{
    return opt_setint(L, fd, SOL_TCP, TCP_KEEPCNT);
}

static int opt_set_tcp_fastopen(lua_State *L, int fd)
{
    return opt_setint(L, fd, SOL_TCP, TCP_FASTOPEN);
}

static int opt_set_tcp_nodelay(lua_State *L, int fd)
{
    return opt_setboolean(L, fd, IPPROTO_TCP, TCP_NODELAY);
}

static int opt_set_ipv6_v6only(lua_State *L, int fd)
{
    return opt_setboolean(L, fd, IPPROTO_IPV6, IPV6_V6ONLY);
}

static int opt_set_bindtodevice(lua_State *L, int fd)
{
    const char *ifname = luaL_checkstring(L, 3);
    struct ifreq ifr = {};

    if (strlen(ifname) >= IFNAMSIZ)
        luaL_argerror(L, 3, "ifname too long");

    strcpy(ifr.ifr_name, ifname);

    return opt_set(L, fd, SOL_SOCKET, SO_BINDTODEVICE, &ifr, sizeof(ifr));
}

static struct sock_opt optset[] = {
    {"reuseaddr", opt_set_reuseaddr},
    {"reuseport", opt_set_reuseport},
    {"keepalive", opt_set_keepalive},
    {"tcp_keepidle", opt_set_tcp_keepidle},
    {"tcp_keepintvl", opt_set_tcp_keepintvl},
    {"tcp_keepcnt", opt_set_tcp_keepcnt},
    {"tcp_fastopen", opt_set_tcp_fastopen},
    {"tcp_nodelay", opt_set_tcp_nodelay},
    {"ipv6_v6only", opt_set_ipv6_v6only},
    {"bindtodevice", opt_set_bindtodevice},
    {NULL, NULL}
};

static int eco_socket_setoption(lua_State *L)
{
    int fd = luaL_checkinteger(L, 1);
    const char *name = luaL_checkstring(L, 2);
    struct sock_opt *o = optset;

    while (o->name && strcmp(name, o->name))
        o++;

    if (!o->func) {
        char msg[60];
        sprintf(msg, "unsupported option '%.35s'", name);
        luaL_argerror(L, 2, msg);
    }

    return o->func(L, fd);
}

static int eco_socket_is_ipv4_address(lua_State *L)
{
    const char *ip = luaL_checkstring(L, 1);
    struct in_addr addr;

    lua_pushboolean(L, inet_pton(AF_INET, ip, &addr) == 1);
    return 1;
}

static int eco_socket_is_ipv6_address(lua_State *L)
{
    const char *ip = luaL_checkstring(L, 1);
    struct in6_addr addr;

    lua_pushboolean(L, inet_pton(AF_INET6, ip, &addr) == 1);
    return 1;
}

int luaopen_eco_core_socket(lua_State *L)
{
    lua_newtable(L);

    lua_add_constant(L, "AF_INET", AF_INET);
    lua_add_constant(L, "AF_INET6", AF_INET6);
    lua_add_constant(L, "AF_UNIX", AF_UNIX);

    lua_add_constant(L, "SOCK_DGRAM", SOCK_DGRAM);
    lua_add_constant(L, "SOCK_STREAM", SOCK_STREAM);

    /* Bits in the FLAGS argument to `send', `recv' */
    lua_add_constant(L, "MSG_OOB", MSG_OOB);
    lua_add_constant(L, "MSG_PEEK", MSG_PEEK);
    lua_add_constant(L, "MSG_DONTROUTE", MSG_DONTROUTE);
    lua_add_constant(L, "MSG_TRUNC", MSG_TRUNC);
    lua_add_constant(L, "MSG_DONTWAIT", MSG_DONTWAIT);
    lua_add_constant(L, "MSG_EOR", MSG_EOR);
    lua_add_constant(L, "MSG_WAITALL", MSG_WAITALL);
    lua_add_constant(L, "MSG_CONFIRM", MSG_CONFIRM);
    lua_add_constant(L, "MSG_ERRQUEUE", MSG_ERRQUEUE);
    lua_add_constant(L, "MSG_NOSIGNAL", MSG_NOSIGNAL);
    lua_add_constant(L, "MSG_MORE", MSG_MORE);
    lua_add_constant(L, "MSG_CMSG_CLOEXEC", MSG_CMSG_CLOEXEC);

    lua_pushcfunction(L, eco_socket_socket);
    lua_setfield(L, -2, "socket");

    lua_pushcfunction(L, eco_socket_bind);
    lua_setfield(L, -2, "bind");

    lua_pushcfunction(L, eco_socket_bind6);
    lua_setfield(L, -2, "bind6");

    lua_pushcfunction(L, eco_socket_bind_unix);
    lua_setfield(L, -2, "bind_unix");

    lua_pushcfunction(L, eco_socket_listen);
    lua_setfield(L, -2, "listen");

    lua_pushcfunction(L, eco_socket_accept);
    lua_setfield(L, -2, "accept");

    lua_pushcfunction(L, eco_socket_connect);
    lua_setfield(L, -2, "connect");

    lua_pushcfunction(L, eco_socket_connect6);
    lua_setfield(L, -2, "connect6");

    lua_pushcfunction(L, eco_socket_connect_unix);
    lua_setfield(L, -2, "connect_unix");

    lua_pushcfunction(L, eco_socket_send);
    lua_setfield(L, -2, "send");

    lua_pushcfunction(L, eco_socket_recv);
    lua_setfield(L, -2, "recv");

    lua_pushcfunction(L, eco_socket_sendto);
    lua_setfield(L, -2, "sendto");

    lua_pushcfunction(L, eco_socket_sendto6);
    lua_setfield(L, -2, "sendto6");

    lua_pushcfunction(L, eco_socket_sendto_unix);
    lua_setfield(L, -2, "sendto_unix");

    lua_pushcfunction(L, eco_socket_recvfrom);
    lua_setfield(L, -2, "recvfrom");

    lua_pushcfunction(L, eco_socket_getsockname);
    lua_setfield(L, -2, "getsockname");

    lua_pushcfunction(L, eco_socket_getpeername);
    lua_setfield(L, -2, "getpeername");

    lua_pushcfunction(L, eco_socket_getoption);
    lua_setfield(L, -2, "getoption");

    lua_pushcfunction(L, eco_socket_setoption);
    lua_setfield(L, -2, "setoption");

    lua_pushcfunction(L, eco_socket_is_ipv4_address);
    lua_setfield(L, -2, "is_ipv4_address");

    lua_pushcfunction(L, eco_socket_is_ipv6_address);
    lua_setfield(L, -2, "is_ipv6_address");

    return 1;
}
