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

#include <linux/rtnetlink.h>
#include <linux/if_link.h>
#include <libmnl/libmnl.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <net/if.h>
#include <stdlib.h>
#include <errno.h>
#include <time.h>

#include "eco.h"

struct eco_ip {
    struct eco_context *ctx;
    struct mnl_socket *nl;
    unsigned int portid;
    unsigned int seq;
    struct ev_timer tmr;
    struct ev_io io;
    lua_State *co;
    mnl_cb_t cb;
    struct {
        int ifindex;
    } filter;
    bool dump;
    int num;
    char buf[0];
};

struct eco_ip_addr {
    int family;
    int prefix;
    int len;
    union {
        in_addr_t ip;
        struct in6_addr ip6;
    } addr;
};

static int rtscope_aton(const char *str)
{
    unsigned long res;
    char *end;

    if (!strcmp(str, "global"))
        return RT_SCOPE_UNIVERSE;
    if (!strcmp(str, "nowhere"))
        return RT_SCOPE_NOWHERE;
    if (!strcmp(str, "host"))
        return RT_SCOPE_HOST;
    if (!strcmp(str, "link"))
        return RT_SCOPE_LINK;
    if (!strcmp(str, "site"))
        return RT_SCOPE_SITE;

    res = strtoul(str, &end, 0);
    if (!end || end == str || *end || res > 255)
        return -1;

    return (int)res;
}

static const char *family_name(int family)
{
    if (family == AF_INET)
        return "inet";
    if (family == AF_INET6)
        return "inet6";
    if (family == AF_PACKET)
        return "link";
    if (family == AF_MPLS)
        return "mpls";
    if (family == AF_BRIDGE)
        return "bridge";
    return "???";
}

static void eco_ip_io_cb(struct ev_loop *loop, ev_io *w, int revents)
{
    struct eco_ip *ip = container_of(w, struct eco_ip, io);
    lua_State *co = ip->co;
    int ret;

    ret = mnl_socket_recvfrom(ip->nl, ip->buf, MNL_SOCKET_BUFFER_SIZE);
    if (ret != -1)
        ret = mnl_cb_run(ip->buf, ret, ip->seq, ip->portid, ip->cb, ip);
    if (ret == -1){
        ev_io_stop(loop, w);
        lua_pop(co, 1);
        lua_pushnil(co);
        lua_pushstring(co, strerror(errno));
        eco_resume(ip->ctx->L, co, 2);
        return;
    }

    if (ret == MNL_CB_OK)
        return;

    ev_io_stop(loop, w);
    eco_resume(ip->ctx->L, co, 1);
}

static int eco_ip_gc(lua_State *L)
{
    struct eco_ip *ip = lua_touserdata(L, 1);

    if (ip->nl) {
        mnl_socket_close(ip->nl);
        ip->nl = NULL;
    }

    return 0;
}

static int ip_link_show_attr_cb(const struct nlattr *attr, void *data)
{
    const struct nlattr **tb = data;
    int type = mnl_attr_get_type(attr);

    if (type > IFLA_MAX)
        return MNL_CB_OK;
    tb[type] = attr;
    return MNL_CB_OK;
}

static void ip_link_parse(lua_State *co, struct ifinfomsg *ifm, struct nlattr **tb)
{
    struct rtnl_link_stats64 stats = {};
    bool found_stats = false;

    lua_pushboolean(co, ifm->ifi_flags & IFF_RUNNING);
    lua_setfield(co, -2, "up");

    lua_pushboolean(co, ifm->ifi_flags & IFF_NOARP);
    lua_setfield(co, -2, "noarp");

    if (tb[IFLA_ADDRESS]) {
        uint8_t *hwaddr = mnl_attr_get_payload(tb[IFLA_ADDRESS]);
        int addr_len = mnl_attr_get_payload_len(tb[IFLA_ADDRESS]);
        char address[48] = "", *p;
        int i;

        for (i = 0, p = address; i < addr_len; i++) {
            sprintf(p, "%.2x", hwaddr[i] & 0xff);
            p += 2;
            if (i + 1 != addr_len)
                *p++ = ':';
        }
        lua_pushstring(co, address);
        lua_setfield(co, -2, "address");
    }

    if (tb[IFLA_MTU]) {
        lua_pushuint(co, mnl_attr_get_u32(tb[IFLA_MTU]));
        lua_setfield(co, -2, "mtu");
    }

    if (tb[IFLA_QDISC]) {
        lua_pushstring(co, mnl_attr_get_str(tb[IFLA_QDISC]));
        lua_setfield(co, -2, "qdisc");
    }

    if (tb[IFLA_MASTER]) {
        int ifindex = mnl_attr_get_u32(tb[IFLA_MASTER]);
        char ifname[IF_NAMESIZE];

        if_indextoname(ifindex, ifname);
        lua_pushstring(co, ifname);
        lua_setfield(co, -2, "master");
    }

    if (tb[IFLA_TXQLEN]) {
        lua_pushuint(co, mnl_attr_get_u32(tb[IFLA_TXQLEN]));
        lua_setfield(co, -2, "txqlen");
    }

    if (tb[IFLA_IFALIAS]) {
        lua_pushstring(co, mnl_attr_get_str(tb[IFLA_IFALIAS]));
        lua_setfield(co, -2, "ifalias");
    }

    if (tb[IFLA_CARRIER]) {
        lua_pushstring(co, mnl_attr_get_u8(tb[IFLA_CARRIER]) ? "on" : "off");
        lua_setfield(co, -2, "carrier");
    }

    if (tb[IFLA_CARRIER_CHANGES]) {
        uint32_t changes = mnl_attr_get_u32(tb[IFLA_CARRIER_CHANGES]);
        if (changes) {
            lua_pushboolean(co, true);
            lua_setfield(co, -2, "carrier_changes");
        }
    }

    if (tb[IFLA_STATS64]) {
        found_stats = true;
        memcpy(&stats, mnl_attr_get_payload(tb[IFLA_STATS64]), sizeof(struct rtnl_link_stats64));
    } else if (tb[IFLA_STATS]) {
        found_stats = true;
        struct rtnl_link_stats *s = mnl_attr_get_payload(tb[IFLA_STATS]);
        stats.rx_packets = s->rx_packets;
        stats.tx_packets = s->tx_packets;
        stats.rx_bytes = s->rx_bytes;
        stats.tx_bytes = s->tx_bytes;
        stats.rx_errors = s->rx_errors;
        stats.tx_errors = s->tx_errors;
        stats.rx_dropped = s->rx_dropped;
        stats.tx_dropped = s->tx_dropped;
        stats.multicast = s->multicast;
        stats.collisions = s->collisions;
        stats.rx_length_errors = s->rx_length_errors;
        stats.rx_over_errors = s->rx_over_errors;
        stats.rx_crc_errors = s->rx_crc_errors;
        stats.rx_frame_errors = s->rx_frame_errors;
        stats.rx_fifo_errors = s->rx_fifo_errors;
        stats.rx_missed_errors = s->rx_missed_errors;
        stats.tx_aborted_errors = s->tx_aborted_errors;
        stats.tx_carrier_errors = s->tx_carrier_errors;
        stats.tx_fifo_errors = s->tx_fifo_errors;
        stats.tx_heartbeat_errors = s->tx_heartbeat_errors;
        stats.tx_window_errors = s->tx_window_errors;
        stats.rx_compressed = s->rx_compressed;
        stats.tx_compressed = s->tx_compressed;
        stats.rx_nohandler = s->rx_nohandler;
    }

    if (found_stats)  {
        lua_newtable(co);

        lua_pushuint(co, stats.rx_packets);
        lua_setfield(co, -2, "rx_packets");

        lua_pushuint(co, stats.tx_packets);
        lua_setfield(co, -2, "tx_packets");

        lua_pushuint(co, stats.rx_bytes);
        lua_setfield(co, -2, "rx_bytes");

        lua_pushuint(co, stats.tx_bytes);
        lua_setfield(co, -2, "tx_bytes");

        lua_pushuint(co, stats.rx_errors);
        lua_setfield(co, -2, "rx_errors");

        lua_pushuint(co, stats.tx_errors);
        lua_setfield(co, -2, "tx_errors");

        lua_pushuint(co, stats.rx_dropped);
        lua_setfield(co, -2, "rx_dropped");

        lua_pushuint(co, stats.tx_dropped);
        lua_setfield(co, -2, "tx_dropped");

        lua_setfield(co, -2, "stats");
    }
}

static int ip_link_show_cb(const struct nlmsghdr *nlh, void *data)
{
    struct ifinfomsg *ifm = mnl_nlmsg_get_payload(nlh);
    struct nlattr *tb[IFLA_MAX+1] = {};
    struct eco_ip *ip = data;
    lua_State *co = ip->co;

    mnl_attr_parse(nlh, sizeof(struct ifinfomsg), ip_link_show_attr_cb, tb);

    if (ip->dump)
        lua_newtable(co);

    ip_link_parse(co, ifm, tb);

    if (ip->dump)
        lua_setfield(co, -2, mnl_attr_get_str(tb[IFLA_IFNAME]));

    return ip->dump ? MNL_CB_OK : MNL_CB_STOP;
}

static int eco_ip_link_show(struct eco_ip *ip, lua_State *L)
{
    const char *ifname = lua_tostring(L, 3);
    struct nlmsghdr *nlh;
    struct ifinfomsg *ifm;
    bool dump = false;
    unsigned int seq;

    nlh = mnl_nlmsg_put_header(ip->buf);
    nlh->nlmsg_type	= RTM_GETLINK;
    nlh->nlmsg_flags = NLM_F_REQUEST;
    nlh->nlmsg_seq = seq = time(NULL);

    ifm = mnl_nlmsg_put_extra_header(nlh, sizeof(struct ifinfomsg));

    if (ifname) {
        unsigned int ifindex = if_nametoindex(ifname);
        if (ifindex == 0) {
            lua_pushnil(L);
            lua_pushliteral(L, "No such device");
            return 2;
        }
        ifm->ifi_index = ifindex;
    } else {
        nlh->nlmsg_flags |= NLM_F_DUMP;
        dump = true;
    }

    if (mnl_socket_sendto(ip->nl, nlh, nlh->nlmsg_len) < 0) {
        lua_pushnil(L);
        lua_pushstring(L, strerror(errno));
        return 2;
    }

    ev_io_start(ip->ctx->loop, &ip->io);

    ip->co = L;
    ip->seq = seq;
    ip->dump = dump;
    ip->cb = ip_link_show_cb;

    lua_newtable(L);
    return lua_yield(L, 0);
}

static int eco_ip_link_set(struct eco_ip *ip, lua_State *L)
{
    const char *ifname = luaL_checkstring(L, 3);
    struct nlmsghdr *nlh;
    struct ifinfomsg *ifm;
    unsigned int seq;

    nlh = mnl_nlmsg_put_header(ip->buf);
    nlh->nlmsg_type	= RTM_NEWLINK;
    nlh->nlmsg_flags = NLM_F_REQUEST | NLM_F_ACK;
    nlh->nlmsg_seq = seq = time(NULL);

    ifm = mnl_nlmsg_put_extra_header(nlh, sizeof(struct ifinfomsg));

#define link_change(f, v)           \
    do {                            \
        ifm->ifi_change |= f;       \
        if (v)                      \
            ifm->ifi_flags |= f;    \
        else                        \
            ifm->ifi_flags &= ~f;   \
    } while (0)

    if (lua_isstring(L, 4)) {
        const char *opt = lua_tostring(L, 4);
        if (!strcmp(opt, "up")) {
            link_change(IFF_UP, true);
        } else if (!strcmp(opt, "down")) {
            link_change(IFF_UP, false);
        }
    } else if (lua_istable(L, 4)) {
        lua_getfield(L, 4, "up");
        if (lua_isboolean(L, -1)) {
            link_change(IFF_UP, lua_toboolean(L, -1));
            lua_pop(L, 1);
        }

        lua_getfield(L, 4, "down");
        if (lua_isboolean(L, -1)) {
            link_change(IFF_UP, !lua_toboolean(L, -1));
            lua_pop(L, 1);
        }

        lua_getfield(L, 4, "arp");
        if (lua_isboolean(L, -1)) {
            link_change(IFF_NOARP, !lua_toboolean(L, -1));
            lua_pop(L, 1);
        }

        lua_getfield(L, 4, "dynamic");
        if (lua_isboolean(L, -1)) {
            link_change(IFF_DYNAMIC, lua_toboolean(L, -1));
            lua_pop(L, 1);
        }

        lua_getfield(L, 4, "multicast");
        if (lua_isboolean(L, -1)) {
            link_change(IFF_MULTICAST, lua_toboolean(L, -1));
            lua_pop(L, 1);
        }

        lua_getfield(L, 4, "allmulticast");
        if (lua_isboolean(L, -1)) {
            link_change(IFF_ALLMULTI, lua_toboolean(L, -1));
            lua_pop(L, 1);
        }

        lua_getfield(L, 4, "promisc");
        if (lua_isboolean(L, -1)) {
            link_change(IFF_PROMISC, lua_toboolean(L, -1));
            lua_pop(L, 1);
        }

        lua_getfield(L, 4, "trailers");
        if (lua_isboolean(L, -1)) {
            link_change(IFF_NOTRAILERS, !lua_toboolean(L, -1));
            lua_pop(L, 1);
        }

        lua_getfield(L, 4, "carrier");
        if (lua_isboolean(L, -1)) {
            mnl_attr_put_u8(nlh, IFLA_CARRIER, lua_toboolean(L, -1));
            lua_pop(L, 1);
        }

        lua_getfield(L, 4, "txqueuelen");
        if (lua_isnumber(L, -1)) {
            mnl_attr_put_u32(nlh, IFLA_TXQLEN, lua_tointeger(L, -1));
            lua_pop(L, 1);
        }

        lua_getfield(L, 4, "mtu");
        if (lua_isnumber(L, -1)) {
            mnl_attr_put_u32(nlh, IFLA_MTU, lua_tointeger(L, -1));
            lua_pop(L, 1);
        }
    }

    mnl_attr_put_strz(nlh, IFLA_IFNAME, ifname);

    if (mnl_socket_sendto(ip->nl, nlh, nlh->nlmsg_len) < 0) {
        lua_pushnil(L);
        lua_pushstring(L, strerror(errno));
        return 2;
    }

    ev_io_start(ip->ctx->loop, &ip->io);

    ip->co = L;
    ip->seq = seq;

    lua_pushboolean(L, true);
    return lua_yield(L, 0);
}

static int eco_ip_link_del(struct eco_ip *ip, lua_State *L)
{
    const char *ifname = luaL_checkstring(L, 3);
    struct nlmsghdr *nlh;
    unsigned int seq;

    nlh = mnl_nlmsg_put_header(ip->buf);
    nlh->nlmsg_type	= RTM_DELLINK;
    nlh->nlmsg_flags = NLM_F_REQUEST | NLM_F_ACK;
    nlh->nlmsg_seq = seq = time(NULL);

    mnl_nlmsg_put_extra_header(nlh, sizeof(struct rtgenmsg));
    mnl_attr_put_strz(nlh, IFLA_IFNAME, ifname);

    if (mnl_socket_sendto(ip->nl, nlh, nlh->nlmsg_len) < 0) {
        lua_pushnil(L);
        lua_pushstring(L, strerror(errno));
        return 2;
    }

    ev_io_start(ip->ctx->loop, &ip->io);

    ip->co = L;
    ip->seq = seq;

    lua_pushboolean(L, true);
    return lua_yield(L, 0);
}

static int eco_ip_link(lua_State *L)
{
    struct eco_ip *ip = lua_touserdata(L, 1);
    const char *cmd = lua_tostring(L, 2);

    eco_check_context(L);

    ip->dump = false;
    ip->cb = NULL;

    if (!cmd || !strcmp(cmd, "show")) {
        return eco_ip_link_show(ip, L);
    } if (!strcmp(cmd, "set")) {
        return eco_ip_link_set(ip, L);
    } else if (!strcmp(cmd, "delete") || !strcmp(cmd, "del")) {
        return eco_ip_link_del(ip, L);
    } else {
        lua_pushnil(L);
        lua_pushliteral(L, "unknown command");
        return 2;
    }
}

static int ip_addr_show_attr_cb(const struct nlattr *attr, void *data)
{
    const struct nlattr **tb = data;
    int type = mnl_attr_get_type(attr);

    if (type > IFLA_MAX)
        return MNL_CB_OK;
    tb[type] = attr;
    return MNL_CB_OK;
}

static int ip_addr_show_cb(const struct nlmsghdr *nlh, void *data)
{
    struct ifaddrmsg *ifa = mnl_nlmsg_get_payload(nlh);
    struct nlattr *tb[IFLA_MAX + 1] = {};
    struct eco_ip *ip = data;
    lua_State *co = ip->co;
    char ifname[IF_NAMESIZE];

    if (ip->filter.ifindex && ip->filter.ifindex != ifa->ifa_index)
        goto skip;

    mnl_attr_parse(nlh, sizeof(struct ifaddrmsg), ip_addr_show_attr_cb, tb);

    lua_newtable(co);

    lua_pushinteger(co, ifa->ifa_prefixlen);
    lua_setfield(co, -2, "mask");

    if (tb[IFLA_IFNAME]) {
        lua_pushstring(co, mnl_attr_get_str(tb[IFLA_IFNAME]));
    } else {
        if_indextoname(ifa->ifa_index, ifname);
        lua_pushstring(co, ifname);
    }
    lua_setfield(co, -2, "ifname");

    lua_pushstring(co, family_name(ifa->ifa_family));
    lua_setfield(co, -2, "family");

    if (tb[IFA_ADDRESS]) {
        void *addr = mnl_attr_get_payload(tb[IFA_ADDRESS]);
        char out[INET6_ADDRSTRLEN + 4];

        inet_ntop(ifa->ifa_family, addr, out, sizeof(out));
        lua_pushstring(co, out);
        lua_setfield(co, -2, "address");
    }

    if (tb[IFA_BROADCAST]) {
        void *addr = mnl_attr_get_payload(tb[IFA_BROADCAST]);
        char out[INET6_ADDRSTRLEN];

        inet_ntop(ifa->ifa_family, addr, out, sizeof(out));
        lua_pushstring(co, out);
        lua_setfield(co, -2, "broadcast");
    }

    if (tb[IFA_LABEL]) {
        lua_pushstring(co, mnl_attr_get_str(tb[IFA_LABEL]));
        lua_setfield(co, -2, "label");
    }

    lua_rawseti(co, -2, ip->num++);

skip:
    return ip->dump ? MNL_CB_OK : MNL_CB_STOP;
}

static int eco_ip_addr_show(struct eco_ip *ip, lua_State *L)
{
    const char *ifname = lua_tostring(L, 3);
    unsigned int seq, ifindex;
    struct nlmsghdr *nlh;
    struct rtgenmsg *rtm;

    if (ifname) {
        ifindex = if_nametoindex(ifname);
        if (ifindex == 0) {
            lua_pushnil(L);
            lua_pushliteral(L, "No such device");
            return 2;
        }

        ip->filter.ifindex = ifindex;
    }

    nlh = mnl_nlmsg_put_header(ip->buf);
    nlh->nlmsg_type	= RTM_GETADDR;
    nlh->nlmsg_flags = NLM_F_REQUEST | NLM_F_DUMP;
    nlh->nlmsg_seq = seq = time(NULL);

    rtm = mnl_nlmsg_put_extra_header(nlh, sizeof(struct rtgenmsg));
    rtm->rtgen_family = AF_PACKET;

    if (mnl_socket_sendto(ip->nl, nlh, nlh->nlmsg_len) < 0) {
        lua_pushnil(L);
        lua_pushstring(L, strerror(errno));
        return 2;
    }

    ev_io_start(ip->ctx->loop, &ip->io);

    ip->co = L;
    ip->seq = seq;
    ip->dump = true;
    ip->cb = ip_addr_show_cb;

    lua_newtable(L);
    return lua_yield(L, 0);
}

static int eco_ip_parse_addr(lua_State *L, int i, struct eco_ip_addr *addr)
{
    size_t len;
    const char *addrstr = luaL_checklstring(L, i, &len);
    char addrbuf[INET6_ADDRSTRLEN] = "";
    char *p;

    p = strchr(addrstr, '/');
    if (p) {
        len = p - addrstr;
        p++;
    }

    if (len >= INET6_ADDRSTRLEN)
        goto err;

    memcpy(addrbuf, addrstr, len);

    addr->family = AF_INET;
    addr->len = 4;

    if (!inet_pton(AF_INET, addrbuf, &addr->addr)) {
        if (!inet_pton(AF_INET6, addrbuf, &addr->addr))
            goto err;
        addr->family = AF_INET6;
        addr->len = sizeof(struct in6_addr);
    }

    addr->prefix = 0;

    if (p) {
        if (sscanf(p, "%d", &addr->prefix) == 0)
            goto err;

        if (addr->prefix < 0)
            goto err;

        if (addr->family == AF_INET6) {
            if (addr->prefix > 128)
                goto err;
        } else if (addr->prefix > 32)
            goto err;
    }

    return 0;
err:
    return -1;
}

static bool is_valid_label(const char *dev, const char *label)
{
    size_t len = strlen(dev);

    if (strncmp(label, dev, len) != 0)
        return false;

    return label[len] == '\0' || label[len] == ':';
}

static int ipaddr_modify(struct eco_ip *ip, int cmd, int flags, lua_State *L)
{
    const char *ifname = luaL_checkstring(L, 3);
    unsigned int seq, ifindex;
    struct eco_ip_addr addr;
    struct nlmsghdr *nlh;
    struct ifaddrmsg *ifa;
    int scope = 0;

    ifindex = if_nametoindex(ifname);
    if (ifindex == 0) {
        lua_pushnil(L);
        lua_pushliteral(L, "No such device");
        return 2;
    }

    if (eco_ip_parse_addr(L, 4, &addr)) {
        lua_pushnil(L);
        lua_pushliteral(L, "Invalid addr");
        return 2;
    }

    nlh = mnl_nlmsg_put_header(ip->buf);
    nlh->nlmsg_type	= cmd;
    nlh->nlmsg_flags = NLM_F_REQUEST | NLM_F_ACK | flags;
    nlh->nlmsg_seq = seq = time(NULL);

    ifa = mnl_nlmsg_put_extra_header(nlh, sizeof(struct ifaddrmsg));
    ifa->ifa_index = ifindex;

    ifa->ifa_family = addr.family;
    ifa->ifa_prefixlen = addr.prefix;
    mnl_attr_put(nlh, IFA_ADDRESS, addr.len, &addr.addr);

    if (ifa->ifa_family == AF_INET) {
        mnl_attr_put(nlh, IFA_LOCAL, addr.len, &addr.addr);

        if ((addr.addr.ip & 0xFF) == 127)
            scope = RT_SCOPE_HOST;
    }

    if (lua_istable(L, 5)) {
        lua_getfield(L, 5, "scope");
        if (lua_isstring(L, -1) || lua_isnumber(L, -1)) {
            scope = rtscope_aton(lua_tostring(L, -1));
            lua_pop(L, 1);
            if (scope < 0) {
                lua_pushnil(L);
                lua_pushliteral(L, "Invalid scope value");
                return 2;
            }
        }

        lua_getfield(L, 5, "label");
        if (lua_isstring(L, -1)) {
            const char *label = lua_tostring(L, -1);
            if (!is_valid_label(ifname, label)) {
                lua_pushnil(L);
                lua_pushliteral(L, "\"label\" must match \"dev\" or be prefixed by \"dev\" with a colon.");
                return 2;
            }
            mnl_attr_put_strz(nlh, IFA_LABEL, label);
            lua_pop(L, 1);
        }

        lua_getfield(L, 5, "broadcast");
        if (lua_isstring(L, -1)) {
            if (eco_ip_parse_addr(L, -1, &addr) || addr.family != ifa->ifa_family) {
                lua_pushnil(L);
                lua_pushliteral(L, "Invalid broadcast addr");
                return 2;
            }
            mnl_attr_put(nlh, IFA_BROADCAST, addr.len, &addr.addr);
            lua_pop(L, 1);
        }

        lua_getfield(L, 5, "metric");
        if (lua_isnumber(L, -1)) {
            mnl_attr_put_u32(nlh, IFLA_PRIORITY, lua_tointeger(L, -1));
            lua_pop(L, 1);
        }
    }

    ifa->ifa_scope = scope;

    if (mnl_socket_sendto(ip->nl, nlh, nlh->nlmsg_len) < 0) {
        lua_pushnil(L);
        lua_pushstring(L, strerror(errno));
        return 2;
    }

    ev_io_start(ip->ctx->loop, &ip->io);

    ip->co = L;
    ip->seq = seq;

    lua_pushboolean(L, true);
    return lua_yield(L, 0);
}

static int eco_ip_addr(lua_State *L)
{
    struct eco_ip *ip = lua_touserdata(L, 1);
    const char *cmd = lua_tostring(L, 2);

    eco_check_context(L);

    memset(&ip->filter, 0, sizeof(ip->filter));

    ip->dump = false;
    ip->cb = NULL;
    ip->num = 1;

    if (!cmd || !strcmp(cmd, "show")) {
        return eco_ip_addr_show(ip, L);
    } else if (!strcmp(cmd, "add")) {
        return ipaddr_modify(ip, RTM_NEWADDR, NLM_F_CREATE | NLM_F_EXCL, L);
    } else if (!strcmp(cmd, "change")) {
        return ipaddr_modify(ip, RTM_NEWADDR, NLM_F_REPLACE, L);
    } else if (!strcmp(cmd, "replace")) {
        return ipaddr_modify(ip, RTM_NEWADDR, NLM_F_CREATE | NLM_F_REPLACE, L);
    } else if (!strcmp(cmd, "delete") || !strcmp(cmd, "del")) {
        return ipaddr_modify(ip, RTM_DELADDR, 0, L);
    } else {
        lua_pushnil(L);
        lua_pushliteral(L, "unknown command");
        return 2;
    }
}

static void add_drop_membership(struct mnl_socket *nl, int group, bool add)
{
    int op = add ? NETLINK_ADD_MEMBERSHIP : NETLINK_DROP_MEMBERSHIP;
    mnl_socket_setsockopt(nl, op, &group, sizeof(int));
}

static int ip_event_data_attr_cb(const struct nlattr *attr, void *data)
{
    const struct nlattr **tb = data;
    int type = mnl_attr_get_type(attr);

    if (type > IFLA_MAX)
        return MNL_CB_OK;
    tb[type] = attr;
    return MNL_CB_OK;
}

static int ip_event_cb(const struct nlmsghdr *nlh, void *data)
{
    struct ifinfomsg *ifm = mnl_nlmsg_get_payload(nlh);
    struct nlattr *tb[IFLA_MAX + 1] = {};
    struct eco_ip *ip = data;
    lua_State *co = ip->co;
    char ifname[IF_NAMESIZE];

    if (nlh->nlmsg_type != RTM_NEWLINK)
        return MNL_CB_OK;

    ev_timer_stop(ip->ctx->loop, &ip->tmr);

    mnl_attr_parse(nlh, sizeof(struct ifinfomsg), ip_event_data_attr_cb, tb);
    lua_newtable(co);
    ip_link_parse(co, ifm, tb);

    if (tb[IFLA_IFNAME]) {
        lua_pushstring(co, mnl_attr_get_str(tb[IFLA_IFNAME]));
    } else {
        if_indextoname(ifm->ifi_index, ifname);
        lua_pushstring(co, ifname);
    }
    lua_setfield(co, -2, "ifname");

    add_drop_membership(ip->nl, RTNLGRP_LINK, false);
    return MNL_CB_STOP;
}

static void ip_event_timeout_cb(struct ev_loop *loop, ev_timer *w, int revents)
{
    struct eco_ip *ip = container_of(w, struct eco_ip, tmr);
    lua_State *co = ip->co;

    add_drop_membership(ip->nl, RTNLGRP_LINK, false);

    ev_io_stop(ip->ctx->loop, &ip->io);

    lua_pushnil(co);
    lua_pushliteral(co, "timeout");
    eco_resume(ip->ctx->L, co, 2);
}

static int eco_ip_wait(lua_State *L)
{
    struct eco_ip *ip = lua_touserdata(L, 1);
    double timeout = lua_tonumber(L, 2);

    eco_check_context(L);

    ip->cb = ip_event_cb;
    ip->co = L;

    add_drop_membership(ip->nl, RTNLGRP_LINK, true);

    ev_io_start(ip->ctx->loop, &ip->io);

    if (timeout > 0) {
        ev_timer_set(&ip->tmr, timeout, 0.0);
        ev_timer_start(ip->ctx->loop, &ip->tmr);
    }

    return lua_yield(L, 0);
}

static int eco_ip_new(lua_State *L)
{
    struct eco_context *ctx = eco_get_context(L);
    struct mnl_socket *nl;
    struct eco_ip *ip;

    nl = mnl_socket_open2(NETLINK_ROUTE, SOCK_NONBLOCK);
    if (!nl) {
        lua_pushnil(L);
        lua_pushstring(L, strerror(errno));
        return 2;
    }

    if (mnl_socket_bind(nl, 0, MNL_SOCKET_AUTOPID) < 0) {
        lua_pushnil(L);
        lua_pushstring(L, strerror(errno));
        goto err;
    }

    ip = lua_newuserdata(L, sizeof(struct eco_ip) + MNL_SOCKET_BUFFER_SIZE);
    memset(ip, 0, sizeof(struct eco_ip));

    ip->portid = mnl_socket_get_portid(nl);
    ip->ctx = ctx;
    ip->nl = nl;

    lua_pushvalue(L, lua_upvalueindex(1));
    lua_setmetatable(L, -2);

    ev_io_init(&ip->io, eco_ip_io_cb, mnl_socket_get_fd(nl), EV_READ);
    ev_init(&ip->tmr, ip_event_timeout_cb);

    return 1;

err:
    mnl_socket_close(nl);
    return 2;
}

static const struct luaL_Reg ip_metatable[] =  {
    {"__gc", eco_ip_gc},
    {"close", eco_ip_gc},
    {"link", eco_ip_link},
    {"addr", eco_ip_addr},
    {"wait", eco_ip_wait},
    {NULL, NULL}
};

int luaopen_eco_ip(lua_State *L)
{
    lua_newtable(L);

    eco_new_metatable(L, ip_metatable);
    lua_pushcclosure(L, eco_ip_new, 1);
    lua_setfield(L, -2, "new");

    return 1;
}
