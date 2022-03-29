/*
 * MIT License
 *
 * Copyright (c) 2022 Jianhui Zhao <zhaojh329@gmail.com>
 *
 * Reference from: https://raw.githubusercontent.com/cesanta/mongoose/master/src/dns.c
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

#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <stdlib.h>
#include <errno.h>

#include "eco.h"

#define MAXNS 3
#define MAX_ANSWERS 4

struct eco_dns_resolver {
    struct eco_context *ctx;
    struct ev_timer tmr;
    struct ev_io io;
    lua_State *co;
    double timeout;
    char search[512];
    union {
        struct sockaddr addr;
        struct sockaddr_in in;
        struct sockaddr_in6 in6;
    } server[MAXNS];
    struct {
        uint32_t ip[4];
        int nip;
        uint8_t ip6[16][4];
        int nip6;
    } answers;
    int ndns;
    const char *dname;
    uint16_t txnid;
    int nsidx;
    int nreq;
    int fd;
};

struct eco_dns_header {
  uint16_t txnid;  /* Transaction ID */
  uint16_t flags;
  uint16_t questions;
  uint16_t num_answers;
  uint16_t num_authority_prs;
  uint16_t num_other_prs;
};

/* DNS resource record */
struct mg_dns_rr {
    uint16_t nlen;    /* Name or pointer length */
    uint16_t atype;   /* Address type */
    uint16_t aclass;  /* Address class */
    uint16_t alen;    /* Address length */
};

static size_t eco_dns_parse_name_depth(const uint8_t *s, size_t len, size_t ofs,
                                      char *to, size_t tolen, size_t j,
                                      int depth)
{
    size_t i = 0;

    if (tolen > 0 && depth == 0)
        to[0] = '\0';
    if (depth > 5)
        return 0;

    while (ofs + i + 1 < len) {
        size_t n = s[ofs + i];
        if (n == 0) {
            i++;
            break;
        }
        if (n & 0xc0) {
            size_t ptr = (((n & 0x3f) << 8) | s[ofs + i + 1]);  /* 12 is hdr len */
            if (ptr + 1 < len && (s[ptr] & 0xc0) == 0 &&
                eco_dns_parse_name_depth(s, len, ptr, to, tolen, j, depth + 1) == 0)
                return 0;
            i += 2;
            break;
        }
        if (ofs + i + n + 1 >= len)
            return 0;
        if (j > 0) {
            if (j < tolen)
                to[j] = '.';
            j++;
        }
        if (j + n < tolen)
            memcpy(&to[j], &s[ofs + i + 1], n);
        j += n;
        i += n + 1;
        if (j < tolen)
            to[j] = '\0';  /* Zero-terminate this chunk */
    }
    if (tolen > 0)
        to[tolen - 1] = '\0';  /* Make sure make sure it is nul-term */
    return i;
}

static size_t eco_dns_parse_name(const uint8_t *s, size_t n, size_t ofs,
                                char *dst, size_t dstlen)
{
    return eco_dns_parse_name_depth(s, n, ofs, dst, dstlen, 0, 0);
}

size_t eco_dns_parse_rr(const uint8_t *buf, size_t len, size_t ofs,
                       bool is_question, struct mg_dns_rr *rr)
{
    const uint8_t *s = buf + ofs, *e = &buf[len];

    memset(rr, 0, sizeof(*rr));
    if (len < sizeof(struct eco_dns_header))
        return 0;  /* Too small */
    if (len > 512)
        return 0;  /*  Too large, we don't expect that */
    if (s >= e)
        return 0;  /* Overflow */

    if ((rr->nlen = (uint16_t)eco_dns_parse_name(buf, len, ofs, NULL, 0)) == 0)
        return 0;
    s += rr->nlen + 4;
    if (s > e)
        return 0;
    rr->atype = (uint16_t)(((uint16_t)s[-4] << 8) | s[-3]);
    rr->aclass = (uint16_t)(((uint16_t)s[-2] << 8) | s[-1]);
    if (is_question)
        return (size_t)(rr->nlen + 4);

    s += 6;
    if (s > e)
        return 0;
    rr->alen = (uint16_t)(((uint16_t) s[-2] << 8) | s[-1]);
    if (s + rr->alen > e)
        return 0;
    return (size_t)(rr->nlen + rr->alen + 10);
}

static void eco_dns_parse(struct eco_dns_resolver *res, const uint8_t *buf, size_t len)
{
    const struct eco_dns_header *h = (struct eco_dns_header *)buf;
    size_t i, n, ofs = sizeof(struct eco_dns_header);
    struct mg_dns_rr rr;
    char name[256] = "";

    if (len < sizeof(*h))
        return;  /* Too small, headers dont fit */
    if (ntohs(h->questions) > 1)
        return;  /* Sanity */
    if (ntohs(h->num_answers) > 10)
        return;  /* Sanity */

    if (ntohs(h->txnid) != res->txnid)
        return;

    for (i = 0; i < ntohs(h->questions); i++) {
        if ((n = eco_dns_parse_rr(buf, len, ofs, true, &rr)) == 0)
            return;
        ofs += n;
    }
    for (i = 0; i < ntohs(h->num_answers); i++) {
        if ((n = eco_dns_parse_rr(buf, len, ofs, false, &rr)) == 0)
            return;
        eco_dns_parse_name(buf, len, ofs, name, sizeof(name));
        ofs += n;

        if (rr.alen == 4 && rr.atype == 1 && rr.aclass == 1) {
            if (res->answers.nip == MAX_ANSWERS)
                continue;
            memcpy(&res->answers.ip[res->answers.nip++], &buf[ofs - 4], 4);
        } else if (rr.alen == 16 && rr.atype == 28 && rr.aclass == 1) {
            if (res->answers.nip6 == MAX_ANSWERS)
                continue;
            memcpy(&res->answers.ip6[res->answers.nip6++], &buf[ofs - 16], 16);
        }
    }

    res->nreq--;
}

static int send_dns_req(struct eco_dns_resolver *res);

static void query_clean(struct eco_dns_resolver *res)
{
    struct ev_loop *loop = res->ctx->loop;

    ev_timer_stop(loop, &res->tmr);

    if (res->fd > -1) {
        ev_io_stop(loop, &res->io);
        close(res->fd);
        res->fd = -1;
    }

    res->nreq = 0;
    res->answers.nip = 0;
    res->answers.nip6 = 0;
    res->nsidx = 0;
    res->co = NULL;
}

static void eco_dns_timer_cb(struct ev_loop *loop, ev_timer *w, int revents)
{
    struct eco_dns_resolver *res = container_of(w, struct eco_dns_resolver, tmr);
    ev_io_stop(loop, &res->io);
    send_dns_req(res);
}

static void eco_dns_io_cb(struct ev_loop *loop, ev_io *w, int revents)
{
    struct eco_dns_resolver *res = container_of(w, struct eco_dns_resolver, io);
    lua_State *co = res->co;
    char buf[1024];
    int r, i, idx = 1;

    r = read(w->fd, buf, sizeof(buf));
    if (r < 0) {
        query_clean(res);
        lua_pushnil(co);
        lua_pushstring(co, strerror(errno));
        eco_resume(res->ctx->L, co, 2);
        return;
    }

    eco_dns_parse(res, (const uint8_t *)buf, r);

    if (res->nreq)
        return;

    lua_newtable(co);

    for (i = 0; i < res->answers.nip; i++) {
        inet_ntop(AF_INET, &res->answers.ip[i], buf, sizeof(buf));
        lua_pushstring(co, buf);
        lua_rawseti(co, -2, idx++);
    }

    for (i = 0; i < res->answers.nip6; i++) {
        inet_ntop(AF_INET6, &res->answers.ip6[i], buf, sizeof(buf));
        lua_pushstring(co, buf);
        lua_rawseti(co, -2, idx++);
    }

    query_clean(res);
    eco_resume(res->ctx->L, co, 1);
}

static int send_dns_req(struct eco_dns_resolver *res)
{
    struct ev_loop *loop = res->ctx->loop;
    const char *dname = res->dname;
    int dname_len = strnlen(dname, 255);
    struct {
        struct eco_dns_header header;
        uint8_t data[256];
    } pkt = {};
    struct sockaddr_in6 laddr = {};
    struct sockaddr *addr;
    lua_State *co = res->co;
    size_t i, n;
    int fd;

    if (res->nsidx == res->ndns) {
        query_clean(res);
        lua_pushnil(co);
        lua_pushliteral(co, "timeout");
        eco_resume(res->ctx->L, co, 2);
        return 0;
    }

    res->txnid = rand() % 65535;

    addr = &res->server[res->nsidx].addr;
    laddr.sin6_family = addr->sa_family;

    fd = socket(addr->sa_family, SOCK_DGRAM, 0);
    if (fd < 0)
        goto err;

    /* bind() ensures we have a *particular port* selected by kernel
     * and remembered in fd, thus later recv(fd)
	 * receives only packets sent to this port.
    */
    if (bind(fd, (struct sockaddr *)&laddr, sizeof(struct sockaddr_in6)) < 0)
        goto err;

    pkt.header.txnid = htons(res->txnid);
    pkt.header.flags = htons(0x100);
    pkt.header.questions = htons(1);

    for (i = n = 0; i < sizeof(pkt.data) - 5; i++) {
        if (dname[i] == '.' || i >= dname_len) {
            pkt.data[n] = i - n;
            memcpy(&pkt.data[n + 1], dname + n, i - n);
            n = i + 1;
        }
        if (i >= dname_len)
            break;
    }

    memcpy(&pkt.data[n], "\x00\x00\x01\x00\x01", 5);  /* A query */
    n += 5;

    if (sendto(fd, &pkt, sizeof(pkt.header) + n, 0, addr, sizeof(struct sockaddr_in6)) < 0)
        goto err;

    pkt.data[n - 3] = 0x1c;  /* AAAA query */
    if (sendto(fd, &pkt, sizeof(pkt.header) + n, 0, addr, sizeof(struct sockaddr_in6)) < 0)
        goto err;

    ev_timer_set(&res->tmr, res->timeout, 0);
    ev_timer_start(loop, &res->tmr);

    ev_io_init(&res->io, eco_dns_io_cb, fd, EV_READ);
    ev_io_start(loop, &res->io);

    res->nsidx++;
    res->fd = fd;
    res->nreq = 2;

    return 0;

err:
    query_clean(res);

    if (!co)
        return -1;

    lua_pushnil(co);
    lua_pushstring(co, strerror(errno));
    eco_resume(res->ctx->L, co, 2);
    return 0;
}

static int eco_dns_query(lua_State *L)
{
    struct eco_dns_resolver *res = lua_touserdata(L, 1);
    const char *dname = luaL_checkstring(L, 2);
    struct in6_addr sin6_addr;
    struct in_addr sin_addr;

    lua_newtable(L);

    if (inet_pton(AF_INET, dname, &sin_addr) == 1) {
        lua_pushvalue(L, 2);
        lua_rawseti(L, -2, 1);
        return 1;
    }

    if (inet_pton(AF_INET6, dname, &sin6_addr) == 1) {
        lua_pushvalue(L, 2);
        lua_rawseti(L, -2, 1);
        return 1;
    }

    lua_pop(L, 2);

    res->dname = dname;

    if (send_dns_req(res) < 0) {
        lua_pushnil(L);
        lua_pushstring(L, strerror(errno));
        return 2;
    }

    res->co = L;
    return lua_yield(L, 0);
}

static void add_ns(struct eco_dns_resolver *res, const char *nameserver)
{
    struct sockaddr_in *in = NULL;
    struct sockaddr_in6 *in6 = NULL;
    int i;

    if (!nameserver || nameserver[0] == '\0')
        return;

    for (i = 0; i < MAXNS; i++) {
        if (res->server[i].addr.sa_family == 0) {
            in = &res->server[i].in;
            in6 = &res->server[i].in6;
            break;
        }
    }

    if (!in)
        return;

    if (inet_pton(AF_INET, nameserver, &in->sin_addr) == 1) {
        in->sin_family = AF_INET;
        in->sin_port = htons(53);
        res->ndns++;
    } else if (inet_pton(AF_INET6, nameserver, &in6->sin6_addr) == 1) {
        in6->sin6_family = AF_INET6;
        in6->sin6_port = htons(53);
        res->ndns++;
    }
}

static void parse_resolvconf(struct eco_dns_resolver *res)
{
    bool have_search_directive = false;
    char line[512];	/* "search" is defined to be up to 256 chars */
    FILE *fp;

    fp = fopen("/etc/resolv.conf", "r");
    if (!fp)
        return;

    while (fgets(line, sizeof(line), fp)) {
        char *p, *arg;
        char *tokstate;

        p = strtok_r(line, " \t\n", &tokstate);
        if (!p)
            continue;

        arg = strtok_r(NULL, "\n", &tokstate);
        if (!arg)
            continue;

        if (!strcmp(p, "domain")) {
            /* domain DOM */
            if (!have_search_directive)
                goto set_search;
            continue;
        }

        if (!strcmp(p, "search")) {
            char *p;
            /* search DOM1 DOM2... */
            have_search_directive = true;
set_search:
            p = arg;
            while (*p == ' ')
                p++;
            strcpy(res->search, p);
            p = strchr(res->search, ' ');
            if (p)
                *p = '\0';
            continue;
        }

        /* nameserver DNS */
        if (!strcmp(p, "nameserver")) {
            char *p = arg;
            char *q;
            while (*p == ' ')
                p++;
            q = strchr(p, ' ');
            if (q)
                *q = '\0';
            add_ns(res, p);
        }
    }

    fclose(fp);

    if (!res->search[0]) {
        char hostname[512];

        /* default search domain is domain part of hostname */
        if (gethostname(hostname, sizeof(hostname)) == 0) {
            char *d = strchr(hostname, '.');
            if (d)
                strcpy(res->search, d + 1);
        }
    }

#define LONE_CHAR(s,c)  ((s)[0] == (c) && !(s)[1])

    /* Cater for case of "domain ." in resolv.conf */
    if (res->search[0] && LONE_CHAR(res->search, '.'))
        res->search[0] = '\0';
}

static int eco_dns_resolver(lua_State *L)
{
    struct eco_context *ctx = eco_check_context(L);
    struct eco_dns_resolver *res;

    res = lua_newuserdata(L, sizeof(struct eco_dns_resolver));
    memset(res, 0, sizeof(struct eco_dns_resolver));

    ev_init(&res->tmr, eco_dns_timer_cb);

    res->timeout = 3.0;
    res->ctx = ctx;
    res->fd = -1;

    if (lua_istable(L, 1)) {
        /* Use given DNS server if present */
        lua_getfield(L, 1, "nameserver");
        add_ns(res, lua_tostring(L, -1));

        lua_getfield(L, 1, "timeout");
        res->timeout = luaL_optnumber(L, -1, res->timeout);

        lua_pop(L, 2);
    }

    if (res->ndns == 0) {
        parse_resolvconf(res);
        /* Fall back to localhost if we could not find NS in resolv.conf */
        if (res->ndns == 0)
            add_ns(res, "127.0.0.1");
    }

    if (res->ndns == 0) {
        lua_pushnil(L);
        lua_pushliteral(L, "not found valid nameserver");
        return 2;
    }

    lua_pushvalue(L, lua_upvalueindex(1));
    lua_setmetatable(L, -2);

    return 1;
}

static const struct luaL_Reg resolver_metatable[] =  {
    {"query", eco_dns_query},
    {NULL, NULL}
};

int luaopen_eco_dns(lua_State *L)
{
    lua_newtable(L);

    eco_new_metatable(L, resolver_metatable);
    lua_pushcclosure(L, eco_dns_resolver, 1);
    lua_setfield(L, -2, "resolver");

    return 1;
}
