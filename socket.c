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

    fd = accept4(lfd, (struct sockaddr *)&addr, &addrlen, SOCK_NONBLOCK | SOCK_CLOEXEC);
    if (fd < 0) {
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

static int eco_socket_sendto_common(lua_State *L, int fd, const void *data, size_t len,
    struct sockaddr *addr, socklen_t addrlen)
{
    int ret;

again:
    ret = sendto(fd, data, len, 0, addr, addrlen);
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
    struct sockaddr_in addr = {
        .sin_family = AF_INET,
        .sin_port = htons(port)
    };

    if (inet_pton(AF_INET, ip, &addr.sin_addr) != 1)
        luaL_argerror(L, 2, "not a valid IPv4 address");

    return eco_socket_sendto_common(L, fd, data, len, (struct sockaddr *)&addr, sizeof(struct sockaddr_in));
}

static int eco_socket_sendto6(lua_State *L)
{
    int fd = luaL_checkinteger(L, 1);
    size_t len;
    const char *data = luaL_checklstring(L, 2, &len);
    const char *ip = luaL_checkstring(L, 3);
    int port = luaL_checkinteger(L, 4);
    struct sockaddr_in6 addr = {
        .sin6_family = AF_INET6,
        .sin6_port = htons(port)
    };

    if (inet_pton(AF_INET6, ip, &addr.sin6_addr) != 1)
        luaL_argerror(L, 2, "not a valid IPv6 address");

    return eco_socket_sendto_common(L, fd, data, len, (struct sockaddr *)&addr, sizeof(struct sockaddr_in6));
}

static int eco_socket_sendto_unix(lua_State *L)
{
    int fd = luaL_checkinteger(L, 1);
    size_t len;
    const char *data = luaL_checklstring(L, 2, &len);
    const char *path = luaL_checkstring(L, 3);
    struct sockaddr_un addr = {
        .sun_family = AF_UNIX
    };

    if (strlen(path) >= sizeof(addr.sun_path))
        luaL_argerror(L, 2, "path too long");

    strcpy(addr.sun_path, path);

    return eco_socket_sendto_common(L, fd, data, len, (struct sockaddr *)&addr, SUN_LEN(&addr));
}

static int eco_socket_recvfrom(lua_State *L)
{
    int fd = luaL_checkinteger(L, 1);
    size_t n = luaL_optinteger(L, 2, LUAL_BUFFERSIZE);
    union {
        struct sockaddr_un un;
        struct sockaddr_in in;
        struct sockaddr_in6 in6;
    } addr = {};
    socklen_t addrlen = sizeof(addr);
    luaL_Buffer b;
    ssize_t ret;
    char  *p;

    luaL_buffinit(L, &b);

    p = luaL_prepbuffer(&b);

    if (n > LUAL_BUFFERSIZE)
        n = LUAL_BUFFERSIZE;

again:
    ret = recvfrom(fd, p, n, 0, (struct sockaddr *)&addr, &addrlen);
    if (ret < 0) {
        if (errno == EINTR)
            goto again;
        luaL_pushresult(&b);
        lua_pushstring(L, strerror(errno));
        lua_pushnil(L);
        lua_replace(L, -3);
        return 2;
    }

    luaL_addsize(&b, ret);
    luaL_pushresult(&b);
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

    return opt_set(L, fd, level, name, (char *) &val, sizeof(val));
}

static int opt_set_reuseaddr(lua_State *L, int fd)
{
    return opt_setboolean(L, fd, SOL_SOCKET, SO_REUSEADDR);
}

static struct sock_opt optset[] = {
    {"reuseaddr", opt_set_reuseaddr},
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

int luaopen_eco_core_socket(lua_State *L)
{
    lua_newtable(L);

    lua_add_constant(L, "AF_INET", AF_INET);
    lua_add_constant(L, "AF_INET6", AF_INET6);
    lua_add_constant(L, "AF_UNIX", AF_UNIX);

    lua_add_constant(L, "SOCK_DGRAM", SOCK_DGRAM);
    lua_add_constant(L, "SOCK_STREAM", SOCK_STREAM);

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

    return 1;
}
