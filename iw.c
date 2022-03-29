/*
 * MIT License
 *
 * Copyright (c) 2022 Jianhui Zhao <zhaojh329@gmail.com>
 *
 * Some codes references from: https://git.openwrt.org/project/iwinfo.git and
 * https://git.kernel.org/pub/scm/linux/kernel/git/jberg/iw.git
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

#include <linux/genetlink.h>
#include <linux/if_ether.h>
#include <linux/nl80211.h>
#include <libmnl/libmnl.h>
#include <net/if.h>
#include <ctype.h>
#include <errno.h>
#include <time.h>

#include "eco.h"

#define IW_CIPHER_NONE   (1 << 0)
#define IW_CIPHER_WEP40  (1 << 1)
#define IW_CIPHER_TKIP   (1 << 2)
#define IW_CIPHER_WRAP   (1 << 3)
#define IW_CIPHER_CCMP   (1 << 4)
#define IW_CIPHER_WEP104 (1 << 5)
#define IW_CIPHER_AESOCB (1 << 6)
#define IW_CIPHER_CKIP   (1 << 7)
#define IW_CIPHER_GCMP   (1 << 8)

#define IW_KMGMT_NONE    (1 << 0)
#define IW_KMGMT_8021x   (1 << 1)
#define IW_KMGMT_PSK     (1 << 2)
#define IW_KMGMT_SAE     (1 << 3)
#define IW_KMGMT_OWE     (1 << 4)

#define IW_AUTH_OPEN     (1 << 0)
#define IW_AUTH_SHARED   (1 << 1)

struct iw_crypto_entry {
    bool enabled;
    uint8_t wpa_version;
    uint16_t group_ciphers;
    uint16_t pair_ciphers;
    uint8_t auth_suites;
    uint8_t auth_algs;
};

struct eco_iw {
    struct eco_context *ctx;
    struct mnl_socket *nl;
    unsigned int portid;
    unsigned int seq;
    struct ev_timer tmr;
    struct ev_io io;
    lua_State *co;
    mnl_cb_t cb;
    int family;
    bool dump;
    int num;
    struct  {
        uint32_t groups[6];
        int ngroup;
        int wait[4];
        bool any;
    } event;
    char buf[0];
};

static char eco_iw_obj_key;

static void mac_addr_n2a(char *mac_addr, unsigned char *arg)
{
    int i, l;

    for (i = 0, l = 0; i < ETH_ALEN ; i++) {
        if (i == 0) {
            sprintf(mac_addr + l, "%02x", arg[i]);
            l += 2;
        } else {
            sprintf(mac_addr + l, ":%02x", arg[i]);
            l += 3;
        }
    }
}

static int mac_addr_a2n(unsigned char *mac_addr, const char *arg)
{
    int i;

    for (i = 0; i < ETH_ALEN ; i++) {
        int temp;
        char *cp = strchr(arg, ':');
        if (cp) {
            *cp = 0;
            cp++;
        }
        if (sscanf(arg, "%x", &temp) != 1)
            return -1;
        if (temp < 0 || temp > 255)
            return -1;

        mac_addr[i] = temp;
        if (!cp)
            break;
        arg = cp;
    }
    if (i < ETH_ALEN - 1)
        return -1;

    return 0;
}

static const char *channel_width_name(enum nl80211_chan_width width)
{
    switch (width) {
    case NL80211_CHAN_WIDTH_20_NOHT:
        return "20 MHz (no HT)";
    case NL80211_CHAN_WIDTH_20:
        return "20 MHz";
    case NL80211_CHAN_WIDTH_40:
        return "40 MHz";
    case NL80211_CHAN_WIDTH_80:
        return "80 MHz";
    case NL80211_CHAN_WIDTH_80P80:
        return "80+80 MHz";
    case NL80211_CHAN_WIDTH_160:
        return "160 MHz";
    case NL80211_CHAN_WIDTH_5:
        return "5 MHz";
    case NL80211_CHAN_WIDTH_10:
        return "10 MHz";
    default:
        return "unknown";
    }
}

static char *channel_type_name(enum nl80211_channel_type channel_type)
{
    switch (channel_type) {
    case NL80211_CHAN_NO_HT:
        return "NO HT";
    case NL80211_CHAN_HT20:
        return "HT20";
    case NL80211_CHAN_HT40MINUS:
        return "HT40-";
    case NL80211_CHAN_HT40PLUS:
        return "HT40+";
    default:
        return "unknown";
    }
}

static int ieee80211_freq2channel(int freq)
{
    /* see 802.11-2007 17.3.8.3.2 and Annex J */
    if (freq == 2484)
        return 14;
    /* see 802.11ax D6.1 27.3.23.2 and Annex E */
    else if (freq == 5935)
        return 2;
    else if (freq < 2484)
        return (freq - 2407) / 5;
    else if (freq >= 4910 && freq <= 4980)
        return (freq - 4000) / 5;
    else if (freq < 5950)
        return (freq - 5000) / 5;
    else if (freq <= 45000) /* DMG band lower limit */
        /* see 802.11ax D6.1 27.3.23.2 */
        return (freq - 5950) / 5;
    else if (freq >= 58320 && freq <= 70200)
        return (freq - 56160) / 2160;
    else
        return 0;
}

static const char *ifmodes[NL80211_IFTYPE_MAX + 1] = {
    "unspecified",
    "IBSS",
    "managed",
    "AP",
    "AP/VLAN",
    "WDS",
    "monitor",
    "mesh point",
    "P2P-client",
    "P2P-GO",
    "P2P-device",
    "outside context of a BSS",
    "NAN"
};

static const char *iftype_name(enum nl80211_iftype iftype)
{
    static char modebuf[100];

    if (iftype <= NL80211_IFTYPE_MAX && ifmodes[iftype])
        return ifmodes[iftype];
    sprintf(modebuf, "Unknown mode (%d)", iftype);
    return modebuf;
}

static void eco_iw_obj_clean(struct eco_iw *iw)
{
    lua_State *co = iw->co;

    lua_pushlightuserdata(co, &eco_iw_obj_key);
    lua_rawget(co, LUA_REGISTRYINDEX);
    lua_pushlightuserdata(co, iw);   /* table, key */
    lua_rawget(co, -2);              /* table, userdata */
    lua_pushlightuserdata(co, iw);   /* table, userdata, key */
    lua_pushnil(co);                 /* table, userdata, key, nil */
    lua_rawset(co, -4);              /* table, userdata */
    lua_remove(co, -2);              /* userdata */
}

static void eco_iw_io_cb(struct ev_loop *loop, ev_io *w, int revents)
{
    struct eco_iw *iw = container_of(w, struct eco_iw, io);
    lua_State *co = iw->co;
    int narg = 1;
    int ret;

    ret = mnl_socket_recvfrom(iw->nl, iw->buf, MNL_SOCKET_BUFFER_SIZE);
    if (ret != -1)
        ret = mnl_cb_run(iw->buf, ret, iw->seq, iw->portid, iw->cb, iw);
    if (ret == -1) {
        const char *errs;

        if (iw->family == 0) {
            eco_iw_obj_clean(iw);

            if (errno == ENOENT)
                errs = "Not found nl80211";
            else
                errs = strerror(errno);
        } else {
            errs = strerror(errno);
        }

        narg++;
        lua_pop(co, 1);
        lua_pushnil(co);
        lua_pushstring(co, errs);
        goto done;
    }

    if (ret == MNL_CB_OK)
        return;

done:
    ev_io_stop(loop, w);
    eco_resume(iw->ctx->L, co, narg);
}

static int eco_iw_gc(lua_State *L)
{
    struct eco_iw *iw = lua_touserdata(L, 1);

    if (iw->nl) {
        mnl_socket_close(iw->nl);
        iw->nl = NULL;
    }

    return 0;
}

static int eco_iw_send(struct eco_iw *iw, lua_State *L,
    struct nlmsghdr *nlh, mnl_cb_t cb)
{
    if (mnl_socket_sendto(iw->nl, nlh, nlh->nlmsg_len) < 0) {
        lua_pushnil(L);
        lua_pushstring(L, strerror(errno));
        return 2;
    }

    ev_io_start(iw->ctx->loop, &iw->io);

    iw->co = L;
    iw->cb = cb;
    iw->num = 1;
    iw->seq = nlh->nlmsg_seq;
    iw->dump = !!(nlh->nlmsg_flags & NLM_F_DUMP);

    return lua_yield(L, 0);
}

static int eco_iw_add_interface(lua_State *L)
{
    struct eco_iw *iw = lua_touserdata(L, 1);
    int phy = lua_tointeger(L, 2);
    const char *ifname = luaL_checkstring(L, 3);
    const char *tpstr = luaL_checkstring(L, 4);
    unsigned char mac_addr[ETH_ALEN];
    bool found_mac = false;
    bool use_4addr = false;
    struct nlmsghdr *nlh;
    struct genlmsghdr *genl;
    int iftype;

    eco_check_context(L);

    if (if_nametoindex(ifname)) {
        lua_pushboolean(L, false);
        lua_pushliteral(L, "interface exists");
        return 2;
    }

    if (!strcmp(tpstr, "adhoc") || !strcmp(tpstr, "ibss")) {
        iftype = NL80211_IFTYPE_ADHOC;
    } else if (!strcmp(tpstr, "ocb")) {
        iftype = NL80211_IFTYPE_OCB;
    } else if (!strcmp(tpstr, "monitor")) {
        iftype = NL80211_IFTYPE_MONITOR;
    } else if (!strcmp(tpstr, "master") || !strcmp(tpstr, "ap")) {
        iftype = NL80211_IFTYPE_UNSPECIFIED;
    } else if (!strcmp(tpstr, "__ap")) {
        iftype = NL80211_IFTYPE_AP;
    } else if (!strcmp(tpstr, "__ap_vlan")) {
        iftype = NL80211_IFTYPE_AP_VLAN;
    } else if (!strcmp(tpstr, "wds")) {
        iftype = NL80211_IFTYPE_WDS;
    } else if (!strcmp(tpstr, "managed") ||
           !strcmp(tpstr, "mgd") ||
           !strcmp(tpstr, "station")) {
        iftype = NL80211_IFTYPE_STATION;
    } else if (!strcmp(tpstr, "mp") ||
           !strcmp(tpstr, "mesh")) {
        iftype = NL80211_IFTYPE_MESH_POINT;
    } else if (!strcmp(tpstr, "__p2pcl")) {
        iftype = NL80211_IFTYPE_P2P_CLIENT;
    } else if (!strcmp(tpstr, "__p2pdev")) {
        iftype = NL80211_IFTYPE_P2P_DEVICE;
    } else if (!strcmp(tpstr, "__p2pgo")) {
        iftype = NL80211_IFTYPE_P2P_GO;
    } else if (!strcmp(tpstr, "__nan")) {
        iftype = NL80211_IFTYPE_NAN;
    } else {
        lua_pushboolean(L, false);
        lua_pushliteral(L, "invalid interface type");
        return 2;
    }

    if (lua_istable(L, 5)) {
        const char *addr;

        lua_getfield(L, 5, "addr");
        addr = lua_tostring(L, -1);
        if (addr) {
            if (mac_addr_a2n(mac_addr, addr)) {
                lua_pushboolean(L, false);
                lua_pushliteral(L, "Invalid MAC address");
                return 2;
            }
            found_mac = true;
        }

        lua_getfield(L, 5, "4addr");
        use_4addr = lua_toboolean(L, -1);
    }

    nlh = mnl_nlmsg_put_header(iw->buf);
    nlh->nlmsg_type	= iw->family;
    nlh->nlmsg_flags = NLM_F_REQUEST | NLM_F_ACK;
    nlh->nlmsg_seq = time(NULL);

    genl = mnl_nlmsg_put_extra_header(nlh, sizeof(struct genlmsghdr));
    genl->cmd = NL80211_CMD_NEW_INTERFACE;
    genl->version = 1;

    mnl_attr_put_u32(nlh, NL80211_ATTR_WIPHY, phy);
    mnl_attr_put_u32(nlh, NL80211_ATTR_IFTYPE, iftype);
    mnl_attr_put_strz(nlh, NL80211_ATTR_IFNAME, ifname);

    if (found_mac)
        mnl_attr_put(nlh, NL80211_ATTR_MAC, ETH_ALEN, mac_addr);

    if (use_4addr)
        mnl_attr_put_u8(nlh, NL80211_ATTR_4ADDR, 1);
    else
        mnl_attr_put_u8(nlh, NL80211_ATTR_4ADDR, 0);

    lua_settop(L, 1);
    lua_pushboolean(L, true);
    return eco_iw_send(iw, L, nlh, NULL);
}

static int eco_iw_del_interface(lua_State *L)
{
    struct eco_iw *iw = lua_touserdata(L, 1);
    const char *ifname = luaL_checkstring(L, 2);
    struct nlmsghdr *nlh;
    struct genlmsghdr *genl;
    int ifidx;

    eco_check_context(L);

    ifidx = if_nametoindex(ifname);
    if (ifidx == 0) {
        lua_pushboolean(L, false);
        lua_pushliteral(L, "No such device");
        return 2;
    }

    nlh = mnl_nlmsg_put_header(iw->buf);
    nlh->nlmsg_type	= iw->family;
    nlh->nlmsg_flags = NLM_F_REQUEST | NLM_F_ACK;
    nlh->nlmsg_seq = time(NULL);

    genl = mnl_nlmsg_put_extra_header(nlh, sizeof(struct genlmsghdr));
    genl->cmd = NL80211_CMD_DEL_INTERFACE;
    genl->version = 1;

    mnl_attr_put_u32(nlh, NL80211_ATTR_IFINDEX, ifidx);

    lua_pushboolean(L, true);
    return eco_iw_send(iw, L, nlh, NULL);
}

static int eco_iw_nl80211_attr_cb(const struct nlattr *attr, void *data)
{
    const struct nlattr **tb = data;
    int type = mnl_attr_get_type(attr);

    if (type > NL80211_ATTR_MAX)
        return MNL_CB_OK;
    tb[type] = attr;
    return MNL_CB_OK;
}

static int eco_iw_dev_cb(const struct nlmsghdr *nlh, void *data)
{
    struct nlattr *tb[NL80211_ATTR_MAX + 1] = {};
    struct eco_iw *iw = data;
    lua_State *co = iw->co;
    char macaddr[6 * 3];

    mnl_attr_parse(nlh, sizeof(struct genlmsghdr), eco_iw_nl80211_attr_cb, tb);

    if (!tb[NL80211_ATTR_IFNAME])
        return MNL_CB_OK;

    if (iw->dump)
        lua_newtable(co);

    if (tb[NL80211_ATTR_WIPHY]) {
        lua_pushinteger(co, mnl_attr_get_u32(tb[NL80211_ATTR_WIPHY]));
        lua_setfield(co, -2, "phy");
    }

    if (tb[NL80211_ATTR_MAC]) {
        mac_addr_n2a(macaddr, mnl_attr_get_payload(tb[NL80211_ATTR_MAC]));
        lua_pushstring(co, macaddr);
        lua_setfield(co, -2, "macaddr");
    }

    if (tb[NL80211_ATTR_SSID]) {
        lua_pushlstring(co, mnl_attr_get_payload(tb[NL80211_ATTR_SSID]),
            mnl_attr_get_len(tb[NL80211_ATTR_SSID]));
        lua_setfield(co, -2, "ssid");
    }

    if (tb[NL80211_ATTR_IFTYPE]) {
        lua_pushstring(co, iftype_name(mnl_attr_get_u32(tb[NL80211_ATTR_IFTYPE])));
        lua_setfield(co, -2, "type");
    }

    if (tb[NL80211_ATTR_WIPHY_TX_POWER_LEVEL]) {
        int dbm = mnl_attr_get_u32(tb[NL80211_ATTR_WIPHY_TX_POWER_LEVEL]) / 100;
        lua_pushinteger(co, dbm);
        lua_setfield(co, -2, "txpower");
    }

    if (tb[NL80211_ATTR_4ADDR]) {
        lua_pushboolean(co, mnl_attr_get_u8(tb[NL80211_ATTR_4ADDR]));
        lua_setfield(co, -2, "4addr");
    }

    if (tb[NL80211_ATTR_WIPHY_FREQ]) {
        uint32_t freq = mnl_attr_get_u32(tb[NL80211_ATTR_WIPHY_FREQ]);

        lua_pushinteger(co, freq);
        lua_setfield(co, -2, "freq");

        lua_pushinteger(co, ieee80211_freq2channel(freq));
        lua_setfield(co, -2, "channel");

        if (tb[NL80211_ATTR_CHANNEL_WIDTH]) {
            lua_pushstring(co, channel_width_name(mnl_attr_get_u32(tb[NL80211_ATTR_CHANNEL_WIDTH])));
            lua_setfield(co, -2, "width");

            if (tb[NL80211_ATTR_CENTER_FREQ1]) {
                lua_pushinteger(co, mnl_attr_get_u32(tb[NL80211_ATTR_CENTER_FREQ1]));
                lua_setfield(co, -2, "center_freq1");
            }

            if (tb[NL80211_ATTR_CENTER_FREQ2]) {
                lua_pushinteger(co, mnl_attr_get_u32(tb[NL80211_ATTR_CENTER_FREQ2]));
                lua_setfield(co, -2, "center_freq2");
            }
        } else if (tb[NL80211_ATTR_WIPHY_CHANNEL_TYPE]) {
            enum nl80211_channel_type channel_type;
            channel_type = mnl_attr_get_u32(tb[NL80211_ATTR_WIPHY_CHANNEL_TYPE]);
            lua_pushstring(co, channel_type_name(channel_type));
            lua_setfield(co, -2, "width");
        }
    }

    if (iw->dump)
        lua_setfield(co, -2, mnl_attr_get_str(tb[NL80211_ATTR_IFNAME]));

    return iw->dump ? MNL_CB_OK : MNL_CB_STOP;
}

static int eco_iw_devinfo(lua_State *L)
{
    struct eco_iw *iw = lua_touserdata(L, 1);
    const char *ifname = lua_tostring(L, 2);
    struct nlmsghdr *nlh;
    struct genlmsghdr *genl;
    unsigned int ifidx = 0;

    eco_check_context(L);

    if (ifname) {
        ifidx = if_nametoindex(ifname);
        if (ifidx == 0) {
            lua_pushboolean(L, false);
            lua_pushliteral(L, "No such device");
            return 2;
        }
    }

    nlh = mnl_nlmsg_put_header(iw->buf);
    nlh->nlmsg_type	= iw->family;
    nlh->nlmsg_flags = NLM_F_REQUEST;
    nlh->nlmsg_seq = time(NULL);

    genl = mnl_nlmsg_put_extra_header(nlh, sizeof(struct genlmsghdr));
    genl->cmd = NL80211_CMD_GET_INTERFACE;
    genl->version = 1;

    if (ifidx)
        mnl_attr_put_u32(nlh, NL80211_ATTR_IFINDEX, ifidx);
    else
        nlh->nlmsg_flags = NLM_F_REQUEST | NLM_F_DUMP;

    lua_newtable(L);
    return eco_iw_send(iw, L, nlh, eco_iw_dev_cb);
}

static void add_drop_membership(struct eco_iw *iw, bool add)
{
    int op = add ? NETLINK_ADD_MEMBERSHIP : NETLINK_DROP_MEMBERSHIP;
    int i;

    for (i = 0; i < iw->event.ngroup; i++)
        mnl_socket_setsockopt(iw->nl, op, &iw->event.groups[i], sizeof(uint32_t));
}

static int eco_iw_event_cb(const struct nlmsghdr *nlh, void *data)
{
    struct genlmsghdr *genl = mnl_nlmsg_get_payload(nlh);
    struct nlattr *tb[NL80211_ATTR_MAX + 1] = {};
    struct eco_iw *iw = data;
    lua_State *co = iw->co;
    char ifname[IF_NAMESIZE];
    int cmd = genl->cmd;

    if (!iw->event.any && !(iw->event.wait[cmd / 32] & (1 << (cmd % 32))))
        return MNL_CB_OK;

    ev_timer_stop(iw->ctx->loop, &iw->tmr);

    mnl_attr_parse(nlh, sizeof(struct genlmsghdr), eco_iw_nl80211_attr_cb, tb);

    lua_newtable(co);

    lua_pushinteger(co, cmd);
    lua_setfield(co, -2, "cmd");

    if (tb[NL80211_ATTR_WIPHY]) {
        lua_pushinteger(co, mnl_attr_get_u32(tb[NL80211_ATTR_WIPHY]));
        lua_setfield(co, -2, "phy");
    }

    if (tb[NL80211_ATTR_IFINDEX]) {
        if_indextoname(mnl_attr_get_u32(tb[NL80211_ATTR_IFINDEX]), ifname);
        lua_pushstring(co, ifname);
        lua_setfield(co, -2, "ifname");
    }

    if (tb[NL80211_ATTR_MAC]) {
        char macbuf[6 * 3];
        mac_addr_n2a(macbuf, mnl_attr_get_payload(tb[NL80211_ATTR_MAC]));
        lua_pushstring(co, macbuf);
        lua_setfield(co, -2, "macaddr");
    }

    add_drop_membership(iw, false);
    return MNL_CB_STOP;
}

static void eco_iw_timeout_cb(struct ev_loop *loop, ev_timer *w, int revents)
{
    struct eco_iw *iw = container_of(w, struct eco_iw, tmr);
    lua_State *co = iw->co;

    add_drop_membership(iw, false);

    ev_io_stop(iw->ctx->loop, &iw->io);

    lua_pushnil(co);
    lua_pushliteral(co, "timeout");
    eco_resume(iw->ctx->L, co, 2);
}

static int eco_iw_wait(lua_State *L)
{
    struct eco_iw *iw = lua_touserdata(L, 1);
    double timeout = lua_tonumber(L, 2);
    int top = lua_gettop(L);

    eco_check_context(L);

    memset(iw->event.wait, 0, sizeof(iw->event.wait));

    iw->cb = eco_iw_event_cb;
    iw->event.any = true;
    iw->co = L;

    while (top > 2) {
        int cmd = lua_tointeger(L, top--);

        if (cmd > 0 && cmd < NL80211_CMD_MAX) {
            iw->event.wait[cmd / 32] |= (1 << (cmd % 32));
            iw->event.any = false;
        }
    }

    ev_io_start(iw->ctx->loop, &iw->io);

    if (timeout > 0) {
        ev_timer_set(&iw->tmr, timeout, 0.0);
        ev_timer_start(iw->ctx->loop, &iw->tmr);
    }

    add_drop_membership(iw, true);

    return lua_yield(L, 0);
}

static int eco_iw_scan_trigger(lua_State *L)
{
    struct eco_iw *iw = lua_touserdata(L, 1);
    const char *ifname = luaL_checkstring(L, 2);
    struct nlmsghdr *nlh;
    struct genlmsghdr *genl;
    int ifidx;

    eco_check_context(L);

    ifidx = if_nametoindex(ifname);
    if (ifidx == 0) {
        lua_pushboolean(L, false);
        lua_pushliteral(L, "No such device");
        return 2;
    }

    nlh = mnl_nlmsg_put_header(iw->buf);
    nlh->nlmsg_type	= iw->family;
    nlh->nlmsg_flags = NLM_F_REQUEST | NLM_F_ACK;
    nlh->nlmsg_seq = time(NULL);

    genl = mnl_nlmsg_put_extra_header(nlh, sizeof(struct genlmsghdr));
    genl->cmd = NL80211_CMD_TRIGGER_SCAN;
    genl->version = 1;

    mnl_attr_put_u32(nlh, NL80211_ATTR_IFINDEX, ifidx);

    if (lua_istable(L, 3)) {
        struct nlattr *ssids;

        lua_getfield(L, 3, "freq");
        if (lua_isnumber(L, -1)) {
            struct nlattr *freqs = mnl_attr_nest_start(nlh, NL80211_ATTR_SCAN_FREQUENCIES);
            mnl_attr_put_u32(nlh, 0, lua_tointeger(L, -1));
            mnl_attr_nest_end(nlh, freqs);
        } else if (lua_istable(L, -1)) {
            struct nlattr *freqs = mnl_attr_nest_start(nlh, NL80211_ATTR_SCAN_FREQUENCIES);

            lua_pushnil(L);
            while (lua_next(L, -2) != 0) {
                if (lua_isnumber(L, -1))
                    mnl_attr_put_u32(nlh, 0, lua_tointeger(L, -1));
                lua_pop(L, 1);
            }

            mnl_attr_nest_end(nlh, freqs);
        }

        ssids = mnl_attr_nest_start(nlh, NL80211_ATTR_SCAN_SSIDS);
        mnl_attr_put_str(nlh, 0, "");

        lua_getfield(L, 3, "ssid");
        if (lua_isstring(L, -1)) {
            mnl_attr_put_str(nlh, 0, lua_tostring(L, -1));
        } else if (lua_istable(L, -1)) {
            lua_pushnil(L);
            while (lua_next(L, -2) != 0) {
                if (lua_isstring(L, -1))
                    mnl_attr_put_str(nlh, 0, lua_tostring(L, -1));
                lua_pop(L, 1);
            }
        }
        mnl_attr_nest_end(nlh, ssids);
    }

    lua_settop(L, 1);
    lua_pushboolean(L, true);
    return eco_iw_send(iw, L, nlh, NULL);
}

static void iw_parse_rsn_cipher(uint8_t idx, uint16_t *ciphers)
{
    switch (idx) {
    case 0:
        *ciphers |= IW_CIPHER_NONE;
        break;
    case 1:
        *ciphers |= IW_CIPHER_WEP40;
        break;
    case 2:
        *ciphers |= IW_CIPHER_TKIP;
        break;
    case 3:  /* WRAP */
        break;
    case 4:
        *ciphers |= IW_CIPHER_CCMP;
        break;
    case 5:
        *ciphers |= IW_CIPHER_WEP104;
        break;
    case 8:
        *ciphers |= IW_CIPHER_GCMP;
        break;
    case 6:  /* AES-128-CMAC */
    case 7:  /* No group addressed */
    case 9:  /* GCMP-256 */
    case 10: /* CCMP-256 */
    case 11: /* BIP-GMAC-128 */
    case 12: /* BIP-GMAC-256 */
    case 13: /* BIP-CMAC-256 */
        break;
    }
}

static void iw_parse_rsn(struct iw_crypto_entry *c, uint8_t *data, uint8_t len,
                      uint16_t defcipher, uint8_t defauth)
{
    static unsigned char ms_oui[3]        = { 0x00, 0x50, 0xf2 };
    static unsigned char ieee80211_oui[3] = { 0x00, 0x0f, 0xac };
    uint16_t i, count;
    uint8_t wpa_version = 0;

    data += 2;
    len -= 2;

    if (!memcmp(data, ms_oui, 3))
        wpa_version |= 1;
    else if (!memcmp(data, ieee80211_oui, 3))
        wpa_version |= 2;

    if (len < 4) {
        c->group_ciphers |= defcipher;
        c->pair_ciphers  |= defcipher;
        c->auth_suites   |= defauth;
        return;
    }

    if (!memcmp(data, ms_oui, 3) || !memcmp(data, ieee80211_oui, 3))
        iw_parse_rsn_cipher(data[3], &c->group_ciphers);

    data += 4;
    len -= 4;

    if (len < 2) {
        c->pair_ciphers |= defcipher;
        c->auth_suites  |= defauth;
        return;
    }

    count = data[0] | (data[1] << 8);
    if (2 + (count * 4) > len)
        return;

    for (i = 0; i < count; i++)
        if (!memcmp(data + 2 + (i * 4), ms_oui, 3) ||
            !memcmp(data + 2 + (i * 4), ieee80211_oui, 3))
            iw_parse_rsn_cipher(data[2 + (i * 4) + 3], &c->pair_ciphers);

    data += 2 + (count * 4);
    len -= 2 + (count * 4);

    if (len < 2) {
        c->auth_suites |= defauth;
        return;
    }

    count = data[0] | (data[1] << 8);
    if (2 + (count * 4) > len)
        return;

    for (i = 0; i < count; i++) {
        if (!memcmp(data + 2 + (i * 4), ms_oui, 3) ||
            !memcmp(data + 2 + (i * 4), ieee80211_oui, 3)) {
            switch (data[2 + (i * 4) + 3]) {
            case 1:  /* IEEE 802.1x */
                c->wpa_version |= wpa_version;
                c->auth_suites |= IW_KMGMT_8021x;
                break;

            case 2:  /* PSK */
                c->wpa_version |= wpa_version;
                c->auth_suites |= IW_KMGMT_PSK;
                break;

            case 3:  /* FT/IEEE 802.1X */
            case 4:  /* FT/PSK */
            case 5:  /* IEEE 802.1X/SHA-256 */
            case 6:  /* PSK/SHA-256 */
            case 7:  /* TPK Handshake */
                break;

            case 8:  /* SAE */
                c->wpa_version |= 4;
                c->auth_suites |= IW_KMGMT_SAE;
                break;

            case 9:  /* FT/SAE */
            case 10: /* undefined */
                break;

            case 11: /* 802.1x Suite-B */
            case 12: /* 802.1x Suite-B-192 */
                c->wpa_version |= 4;
                c->auth_suites |= IW_KMGMT_8021x;
                break;

            case 13: /* FT/802.1x SHA-384 */
            case 14: /* FILS SHA-256 */
            case 15: /* FILS SHA-384 */
            case 16: /* FT/FILS SHA-256 */
            case 17: /* FT/FILS SHA-384 */
                break;

            case 18: /* OWE */
                c->wpa_version |= 4;
                c->auth_suites |= IW_KMGMT_OWE;
                break;
            }
        }
    }

    data += 2 + (count * 4);
    len -= 2 + (count * 4);
}

/* Build a short textual description of the crypto info */
static char * iw_crypto_print_ciphers(int ciphers)
{
    static char str[128] = { 0 };
    char *pos = str;

    if (ciphers & IW_CIPHER_WEP40)
        pos += sprintf(pos, "WEP-40, ");

    if (ciphers & IW_CIPHER_WEP104)
        pos += sprintf(pos, "WEP-104, ");

    if (ciphers & IW_CIPHER_TKIP)
        pos += sprintf(pos, "TKIP, ");

    if (ciphers & IW_CIPHER_CCMP)
        pos += sprintf(pos, "CCMP, ");

    if (ciphers & IW_CIPHER_GCMP)
        pos += sprintf(pos, "GCMP, ");

    if (ciphers & IW_CIPHER_WRAP)
        pos += sprintf(pos, "WRAP, ");

    if (ciphers & IW_CIPHER_AESOCB)
        pos += sprintf(pos, "AES-OCB, ");

    if (ciphers & IW_CIPHER_CKIP)
        pos += sprintf(pos, "CKIP, ");

    if (!ciphers || (ciphers & IW_CIPHER_NONE))
        pos += sprintf(pos, "NONE, ");

    *(pos - 2) = 0;

    return str;
}

static char * iw_crypto_print_suites(int suites)
{
    static char str[64] = { 0 };
    char *pos = str;

    if (suites & IW_KMGMT_PSK)
        pos += sprintf(pos, "PSK/");

    if (suites & IW_KMGMT_8021x)
        pos += sprintf(pos, "802.1X/");

    if (suites & IW_KMGMT_SAE)
        pos += sprintf(pos, "SAE/");

    if (suites & IW_KMGMT_OWE)
        pos += sprintf(pos, "OWE/");

    if (!suites || (suites & IW_KMGMT_NONE))
        pos += sprintf(pos, "NONE/");

    *(pos - 1) = 0;

    return str;
}

static char *iw_crypto_desc(struct iw_crypto_entry *c)
{
    static char desc[512] = "";
    char *pos = desc;
    int i, n;

    if (!c)
        return "Unknown";
    if (!c->enabled)
        return "None";

    /* WEP */
    if (c->auth_algs && !c->wpa_version) {
        if ((c->auth_algs & IW_AUTH_OPEN) &&
            (c->auth_algs & IW_AUTH_SHARED)) {
            sprintf(desc, "WEP Open/Shared (%s)",
                iw_crypto_print_ciphers(c->pair_ciphers));
        } else if (c->auth_algs & IW_AUTH_OPEN) {
            sprintf(desc, "WEP Open System (%s)",
                iw_crypto_print_ciphers(c->pair_ciphers));
        } else if (c->auth_algs & IW_AUTH_SHARED) {
            sprintf(desc, "WEP Shared Auth (%s)",
                iw_crypto_print_ciphers(c->pair_ciphers));
        }
        return desc;
    }

    if (!c->wpa_version)
        return "None";

    /* WPA */
    for (i = 0, n = 0; i < 3; i++)
        if (c->wpa_version & (1 << i))
            n++;

    if (n > 1)
        pos += sprintf(pos, "mixed ");

    for (i = 0; i < 3; i++)
        if (c->wpa_version & (1 << i)) {
            if (i)
                pos += sprintf(pos, "WPA%d/", i + 1);
            else
                pos += sprintf(pos, "WPA/");
        }

    pos--;

    sprintf(pos, " %s (%s)", iw_crypto_print_suites(c->auth_suites),
        iw_crypto_print_ciphers(c->pair_ciphers | c->group_ciphers));

    return desc;
}

static void push_cryptotable(lua_State *L, struct iw_crypto_entry *c)
{
    static const char *IW_CIPHER_NAMES[] = {"NONE", "WEP40", "TKIP", "WRAP",
                                            "CCMP", "WEP104", "AES-OCB", "CKIP"};
    static const char *IW_KMGMT_NAMES[] = {"NONE", "802.1X", "PSK"};
    static const char *IW_AUTH_NAMES[] = {"OPEN", "SHARED"};
    int i;

    if (c->enabled && !c->wpa_version) {
        c->auth_algs    = IW_AUTH_OPEN | IW_AUTH_SHARED;
        c->pair_ciphers = IW_CIPHER_WEP40 | IW_CIPHER_WEP104;
    }

    lua_newtable(L);

    lua_pushboolean(L, c->enabled);
    lua_setfield(L, -2, "enabled");

    lua_pushstring(L, iw_crypto_desc(c));
    lua_setfield(L, -2, "description");

    lua_pushboolean(L, (c->enabled && !c->wpa_version));
    lua_setfield(L, -2, "wep");

    lua_pushinteger(L, c->wpa_version);
    lua_setfield(L, -2, "wpa");

    lua_newtable(L);
    for (i = 0; i < ARRAY_SIZE(IW_CIPHER_NAMES); i++) {
        if (c->pair_ciphers & (1 << i)) {
            lua_pushboolean(L, true);
            lua_setfield(L, -2, IW_CIPHER_NAMES[i]);
        }
    }
    lua_setfield(L, -2, "pair_ciphers");

    lua_newtable(L);
    for (i = 0; i < ARRAY_SIZE(IW_CIPHER_NAMES); i++) {
        if (c->group_ciphers & (1 << i)) {
            lua_pushboolean(L, true);
            lua_setfield(L, -2, IW_CIPHER_NAMES[i]);
        }
    }
    lua_setfield(L, -2, "group_ciphers");

    lua_newtable(L);
    for (i = 0; i < ARRAY_SIZE(IW_KMGMT_NAMES); i++) {
        if (c->auth_suites & (1 << i)) {
            lua_pushboolean(L, true);
            lua_setfield(L, -2, IW_KMGMT_NAMES[i]);
        }
    }
    lua_setfield(L, -2, "auth_suites");

    lua_newtable(L);
    for (i = 0; i < ARRAY_SIZE(IW_AUTH_NAMES); i++) {
        if (c->auth_algs & (1 << i)) {
            lua_pushboolean(L, true);
            lua_setfield(L, -2, IW_AUTH_NAMES[i]);
        }
    }
    lua_setfield(L, -2, "auth_algs");
}

static void ieee80211_get_scanlist_ie(struct nlattr **bss, lua_State *co, struct iw_crypto_entry *crypto)
{
    int ielen = mnl_attr_get_len(bss[NL80211_BSS_INFORMATION_ELEMENTS]);
    unsigned char *ie = mnl_attr_get_payload(bss[NL80211_BSS_INFORMATION_ELEMENTS]);
    static unsigned char ms_oui[3] = { 0x00, 0x50, 0xf2 };
    bool found_ssid = false;

    while (ielen >= 2 && ielen >= ie[1]) {
        switch (ie[0]) {
        case 0: /* SSID */
            if (!found_ssid) {
                found_ssid = true;
                lua_pushlstring(co, (char *)ie + 2, ie[1]);
                lua_setfield(co, -2, "ssid");
            }
            break;

        case 114: /* Mesh ID */
            lua_pushlstring(co, (char *)ie + 2, ie[1]);
            lua_setfield(co, -2, "meshid");
            break;

        case 48: /* RSN */
            iw_parse_rsn(crypto, ie + 2, ie[1], IW_CIPHER_CCMP, IW_KMGMT_8021x);
            break;

        case 221: /* Vendor */
            if (ie[1] >= 4 && !memcmp(ie + 2, ms_oui, 3) && ie[5] == 1)
                iw_parse_rsn(crypto, ie + 6, ie[1] - 4, IW_CIPHER_TKIP, IW_KMGMT_PSK);
            break;
        }

        ielen -= ie[1] + 2;
        ie += ie[1] + 2;
    }
}

static int nl80211_parse_bss_cb(const struct nlattr *attr, void *data)
{
    const struct nlattr **tb = data;
    int type = mnl_attr_get_type(attr);

    if (type > NL80211_BSS_MAX)
        return MNL_CB_OK;
    tb[type] = attr;
    return MNL_CB_OK;
}

static int eco_iw_scan_cb(const struct nlmsghdr *nlh, void *data)
{
    struct nlattr *tb[NL80211_ATTR_MAX + 1] = {};
    struct nlattr *bss[NL80211_BSS_MAX + 1] = {};
    struct iw_crypto_entry crypto = {};
    struct eco_iw *iw = data;
    lua_State *co = iw->co;
    char bssid[6 * 3];
    uint16_t caps;

    mnl_attr_parse(nlh, sizeof(struct genlmsghdr), eco_iw_nl80211_attr_cb, tb);

    if (!tb[NL80211_ATTR_BSS])
        return MNL_CB_OK;

    mnl_attr_parse_nested(tb[NL80211_ATTR_BSS], nl80211_parse_bss_cb, bss);

    if (!bss[NL80211_BSS_BSSID])
        return MNL_CB_OK;

    lua_newtable(co);

    if (bss[NL80211_BSS_CAPABILITY])
        caps = mnl_attr_get_u16(bss[NL80211_BSS_CAPABILITY]);
    else
        caps = 0;

    if (caps & (1 << 1))
        lua_pushstring(co, "IBSS");
    else if (caps & (1 << 0))
        lua_pushstring(co, "ESS");
    else
        lua_pushstring(co, "MBSS");

    lua_setfield(co, -2, "mode");

    if (caps & (1 << 4))
        crypto.enabled = true;

    if (bss[NL80211_BSS_SIGNAL_MBM]) {
        uint8_t signal = (uint8_t)((int32_t)mnl_attr_get_u32(bss[NL80211_BSS_SIGNAL_MBM]) / 100);
        int8_t rssi = signal - 0x100;

        if (rssi < -110)
            rssi = -110;
        else if (rssi > -40)
            rssi = -40;

        lua_pushinteger(co, rssi + 110);
        lua_setfield(co, -2, "quality");

        lua_pushinteger(co, 70);
        lua_setfield(co, -2, "quality_max");

        lua_pushinteger(co, signal - 0x100);
        lua_setfield(co, -2, "signal");
    }

    if (bss[NL80211_BSS_FREQUENCY]) {
        lua_pushinteger(co, ieee80211_freq2channel(mnl_attr_get_u32(bss[NL80211_BSS_FREQUENCY])));
        lua_setfield(co, -2, "channel");
    }

    if (bss[NL80211_BSS_INFORMATION_ELEMENTS])
        ieee80211_get_scanlist_ie(bss, co, &crypto);

    push_cryptotable(co, &crypto);
    lua_setfield(co, -2, "encryption");

    mac_addr_n2a(bssid, mnl_attr_get_payload(bss[NL80211_BSS_BSSID]));
    lua_setfield(co, -2, bssid);

    return MNL_CB_OK;
}

static int eco_iw_scan_dump(lua_State *L)
{
    struct eco_iw *iw = lua_touserdata(L, 1);
    const char *ifname = luaL_checkstring(L, 2);
    struct nlmsghdr *nlh;
    struct genlmsghdr *genl;
    unsigned int ifidx;

    eco_check_context(L);

    ifidx = if_nametoindex(ifname);
    if (ifidx == 0) {
        lua_pushboolean(L, false);
        lua_pushliteral(L, "No such device");
        return 2;
    }

    nlh = mnl_nlmsg_put_header(iw->buf);
    nlh->nlmsg_type	= iw->family;
    nlh->nlmsg_flags = NLM_F_REQUEST | NLM_F_DUMP;
    nlh->nlmsg_seq = time(NULL);

    genl = mnl_nlmsg_put_extra_header(nlh, sizeof(struct genlmsghdr));
    genl->cmd = NL80211_CMD_GET_SCAN;
    genl->version = 1;

    mnl_attr_put_u32(nlh, NL80211_ATTR_IFINDEX, ifidx);

    lua_newtable(L);
    return eco_iw_send(iw, L, nlh, eco_iw_scan_cb);
}

static int nl80211_parse_sinfo_cb(const struct nlattr *attr, void *data)
{
    const struct nlattr **tb = data;
    int type = mnl_attr_get_type(attr);

    if (type > NL80211_STA_INFO_MAX)
        return MNL_CB_OK;
    tb[type] = attr;
    return MNL_CB_OK;
}

static int nl80211_parse_rinfo_cb(const struct nlattr *attr, void *data)
{
    const struct nlattr **tb = data;
    int type = mnl_attr_get_type(attr);

    if (type > NL80211_RATE_INFO_MAX)
        return MNL_CB_OK;
    tb[type] = attr;
    return MNL_CB_OK;
}

static void nl80211_parse_rateinfo(struct nlattr **ri, lua_State *L)
{
    bool is_he = false, is_vht = false, is_ht = false, is_short_gi = false;
    int mcs = 0, mhz = 0;
    uint32_t rate = 0;

    if (ri[NL80211_RATE_INFO_BITRATE32])
        rate = mnl_attr_get_u32(ri[NL80211_RATE_INFO_BITRATE32]) * 100;
    else if (ri[NL80211_RATE_INFO_BITRATE])
        rate = mnl_attr_get_u16(ri[NL80211_RATE_INFO_BITRATE]) * 100;

    lua_pushuint(L, rate);
    lua_setfield(L, -2, "rate");

    if (ri[NL80211_RATE_INFO_HE_MCS]) {
        mcs = mnl_attr_get_u8(ri[NL80211_RATE_INFO_HE_MCS]);
        is_he = true;

        if (ri[NL80211_RATE_INFO_HE_NSS]) {
            lua_pushinteger(L, mnl_attr_get_u8(ri[NL80211_RATE_INFO_HE_NSS]));
            lua_setfield(L, -2, "he_nss");
        }

        if (ri[NL80211_RATE_INFO_HE_GI]) {
            lua_pushinteger(L, mnl_attr_get_u8(ri[NL80211_RATE_INFO_HE_GI]));
            lua_setfield(L, -2, "he_gi");
        }

        if (ri[NL80211_RATE_INFO_HE_DCM]) {
            lua_pushinteger(L, mnl_attr_get_u8(ri[NL80211_RATE_INFO_HE_DCM]));
            lua_setfield(L, -2, "he_dcm");
        }
    } else if (ri[NL80211_RATE_INFO_VHT_MCS]) {
        mcs = mnl_attr_get_u8(ri[NL80211_RATE_INFO_VHT_MCS]);
        is_vht = true;

        if (ri[NL80211_RATE_INFO_VHT_NSS]) {
            lua_pushinteger(L, mnl_attr_get_u8(ri[NL80211_RATE_INFO_VHT_NSS]));
            lua_setfield(L, -2, "vht_nss");
        }
    } else if (ri[NL80211_RATE_INFO_MCS]) {
        mcs = mnl_attr_get_u8(ri[NL80211_RATE_INFO_MCS]);
        is_ht = true;
    }

    if (ri[NL80211_RATE_INFO_5_MHZ_WIDTH])
        mhz = 5;
    else if (ri[NL80211_RATE_INFO_10_MHZ_WIDTH])
        mhz = 10;
    else if (ri[NL80211_RATE_INFO_40_MHZ_WIDTH])
        mhz = 40;
    else if (ri[NL80211_RATE_INFO_80_MHZ_WIDTH])
        mhz = 80;
    else if (ri[NL80211_RATE_INFO_80P80_MHZ_WIDTH] ||
             ri[NL80211_RATE_INFO_160_MHZ_WIDTH])
        mhz = 160;
    else
        mhz = 20;

    if (ri[NL80211_RATE_INFO_SHORT_GI])
        is_short_gi = 1;

    lua_pushboolean(L, is_he);
    lua_setfield(L, -2, "he");

    lua_pushboolean(L, is_vht);
    lua_setfield(L, -2, "vht");

    lua_pushboolean(L, is_ht);
    lua_setfield(L, -2, "ht");

    lua_pushboolean(L, is_short_gi);
    lua_setfield(L, -2, "short_gi");

    lua_pushinteger(L, mcs);
    lua_setfield(L, -2, "mcs");

    lua_pushinteger(L, mhz);
    lua_setfield(L, -2, "mhz");
}

static int eco_iw_assoclist_cb(const struct nlmsghdr *nlh, void *data)
{
    struct nlattr *tb[NL80211_ATTR_MAX + 1] = {};
    struct nlattr *sinfo[NL80211_STA_INFO_MAX + 1] = {};
    struct nlattr *rinfo[NL80211_RATE_INFO_MAX + 1] = {};
    struct nl80211_sta_flag_update *sta_flags;
    struct eco_iw *iw = data;
    lua_State *co = iw->co;
    char macbuf[6 * 3];

    mnl_attr_parse(nlh, sizeof(struct genlmsghdr), eco_iw_nl80211_attr_cb, tb);

    if (!tb[NL80211_ATTR_MAC] || !tb[NL80211_ATTR_STA_INFO])
        return MNL_CB_OK;

    lua_newtable(co);

    mnl_attr_parse_nested(tb[NL80211_ATTR_STA_INFO], nl80211_parse_sinfo_cb, sinfo);

    if (sinfo[NL80211_STA_INFO_SIGNAL]) {
        lua_pushinteger(co, mnl_attr_get_u8(sinfo[NL80211_STA_INFO_SIGNAL]));
        lua_setfield(co, -2, "signal");
    }

    if (sinfo[NL80211_STA_INFO_SIGNAL_AVG]) {
        lua_pushinteger(co, mnl_attr_get_u8(sinfo[NL80211_STA_INFO_SIGNAL_AVG]));
        lua_setfield(co, -2, "signal_avg");
    }

    if (sinfo[NL80211_STA_INFO_INACTIVE_TIME]) {
        lua_pushuint(co, mnl_attr_get_u32(sinfo[NL80211_STA_INFO_INACTIVE_TIME]));
        lua_setfield(co, -2, "inactive");
    }

    if (sinfo[NL80211_STA_INFO_CONNECTED_TIME]) {
        lua_pushuint(co, mnl_attr_get_u32(sinfo[NL80211_STA_INFO_CONNECTED_TIME]));
        lua_setfield(co, -2, "connected_time");
    }

    if (sinfo[NL80211_STA_INFO_RX_PACKETS]) {
        lua_pushuint(co, mnl_attr_get_u32(sinfo[NL80211_STA_INFO_RX_PACKETS]));
        lua_setfield(co, -2, "rx_packets");
    }

    if (sinfo[NL80211_STA_INFO_TX_PACKETS]) {
        lua_pushuint(co, mnl_attr_get_u32(sinfo[NL80211_STA_INFO_TX_PACKETS]));
        lua_setfield(co, -2, "tx_packets");
    }

    if (sinfo[NL80211_STA_INFO_RX_BITRATE]) {
        mnl_attr_parse_nested(sinfo[NL80211_STA_INFO_RX_BITRATE], nl80211_parse_rinfo_cb, rinfo);
        lua_newtable(co);
        nl80211_parse_rateinfo(rinfo, co);
        lua_setfield(co, -2, "rx_rate");
    }

    if (sinfo[NL80211_STA_INFO_TX_BITRATE]) {
        mnl_attr_parse_nested(sinfo[NL80211_STA_INFO_TX_BITRATE], nl80211_parse_rinfo_cb, rinfo);
        lua_newtable(co);
        nl80211_parse_rateinfo(rinfo, co);
        lua_setfield(co, -2, "tx_rate");
    }

    if (sinfo[NL80211_STA_INFO_RX_BYTES]) {
        lua_pushuint(co, mnl_attr_get_u32(sinfo[NL80211_STA_INFO_RX_BYTES]));
        lua_setfield(co, -2, "rx_bytes");
    }

    if (sinfo[NL80211_STA_INFO_TX_BYTES]) {
        lua_pushuint(co, mnl_attr_get_u32(sinfo[NL80211_STA_INFO_TX_BYTES]));
        lua_setfield(co, -2, "tx_bytes");
    }

    if (sinfo[NL80211_STA_INFO_TX_RETRIES]) {
        lua_pushuint(co, mnl_attr_get_u32(sinfo[NL80211_STA_INFO_TX_RETRIES]));
        lua_setfield(co, -2, "tx_retries");
    }

    if (sinfo[NL80211_STA_INFO_TX_FAILED]) {
        lua_pushuint(co, mnl_attr_get_u32(sinfo[NL80211_STA_INFO_TX_FAILED]));
        lua_setfield(co, -2, "tx_failed");
    }

    if (sinfo[NL80211_STA_INFO_EXPECTED_THROUGHPUT]) {
        lua_pushuint(co, mnl_attr_get_u32(sinfo[NL80211_STA_INFO_EXPECTED_THROUGHPUT]));
        lua_setfield(co, -2, "thr");
    }

    /* mesh */
    if (sinfo[NL80211_STA_INFO_LLID]) {
        lua_pushuint(co, mnl_attr_get_u32(sinfo[NL80211_STA_INFO_LLID]));
        lua_setfield(co, -2, "llid");
    }

    if (sinfo[NL80211_STA_INFO_PLID]) {
        lua_pushuint(co, mnl_attr_get_u32(sinfo[NL80211_STA_INFO_PLID]));
        lua_setfield(co, -2, "plid");
    }

    /* Station flags */
    if (sinfo[NL80211_STA_INFO_STA_FLAGS]) {
        sta_flags = mnl_attr_get_payload(sinfo[NL80211_STA_INFO_STA_FLAGS]);
        bool authorized, authenticated, short_preamble, wme, mfp, tdls;

        authorized = sta_flags->mask & BIT(NL80211_STA_FLAG_AUTHORIZED) &&
            sta_flags->set & BIT(NL80211_STA_FLAG_AUTHORIZED);
        lua_pushboolean(co, authorized);
        lua_setfield(co, -2, "authorized");

        authenticated = sta_flags->mask & BIT(NL80211_STA_FLAG_AUTHENTICATED) &&
            sta_flags->set & BIT(NL80211_STA_FLAG_AUTHENTICATED);
        lua_pushboolean(co, authenticated);
        lua_setfield(co, -2, "authorized");

        short_preamble = sta_flags->mask & BIT(NL80211_STA_FLAG_SHORT_PREAMBLE) &&
            sta_flags->set & BIT(NL80211_STA_FLAG_SHORT_PREAMBLE);
        lua_pushboolean(co, short_preamble);
        lua_setfield(co, -2, "short_preamble");

        wme = sta_flags->mask & BIT(NL80211_STA_FLAG_WME) &&
            sta_flags->set & BIT(NL80211_STA_FLAG_WME);
        lua_pushboolean(co, wme);
        lua_setfield(co, -2, "wme");

        mfp = sta_flags->mask & BIT(NL80211_STA_FLAG_MFP) &&
            sta_flags->set & BIT(NL80211_STA_FLAG_MFP);
        lua_pushboolean(co, mfp);
        lua_setfield(co, -2, "mfp");

        tdls = sta_flags->mask & BIT(NL80211_STA_FLAG_TDLS_PEER) &&
            sta_flags->set & BIT(NL80211_STA_FLAG_TDLS_PEER);
        lua_pushboolean(co, tdls);
        lua_setfield(co, -2, "tdls");
    }

    mac_addr_n2a(macbuf, mnl_attr_get_payload(tb[NL80211_ATTR_MAC]));
    lua_setfield(co, -2, macbuf);

    return MNL_CB_OK;
}

static int eco_iw_assoclist(lua_State *L)
{
    struct eco_iw *iw = lua_touserdata(L, 1);
    const char *ifname = luaL_checkstring(L, 2);
    struct nlmsghdr *nlh;
    struct genlmsghdr *genl;
    unsigned int ifidx;

    eco_check_context(L);

    ifidx = if_nametoindex(ifname);
    if (ifidx == 0) {
        lua_pushboolean(L, false);
        lua_pushliteral(L, "No such device");
        return 2;
    }

    nlh = mnl_nlmsg_put_header(iw->buf);
    nlh->nlmsg_type	= iw->family;
    nlh->nlmsg_flags = NLM_F_REQUEST | NLM_F_DUMP;
    nlh->nlmsg_seq = time(NULL);

    genl = mnl_nlmsg_put_extra_header(nlh, sizeof(struct genlmsghdr));
    genl->cmd = NL80211_CMD_GET_STATION;
    genl->version = 1;

    mnl_attr_put_u32(nlh, NL80211_ATTR_IFINDEX, ifidx);

    lua_newtable(L);
    return eco_iw_send(iw, L, nlh, eco_iw_assoclist_cb);
}

static int parse_bands_cb(const struct nlattr *attr, void *data)
{
    const struct nlattr **tb = data;
    int type = mnl_attr_get_type(attr);

    if (type > NL80211_BAND_ATTR_MAX)
        return MNL_CB_OK;
    tb[type] = attr;
    return MNL_CB_OK;
}

static int parse_freqs_cb(const struct nlattr *attr, void *data)
{
    const struct nlattr **tb = data;
    int type = mnl_attr_get_type(attr);

    if (type > NL80211_FREQUENCY_ATTR_MAX)
        return MNL_CB_OK;
    tb[type] = attr;
    return MNL_CB_OK;
}

static int eco_iw_freqlist_cb(const struct nlmsghdr *nlh, void *data)
{
    struct nlattr *tb[NL80211_ATTR_MAX + 1] = {};
    struct eco_iw *iw = data;
    lua_State *co = iw->co;
    struct nlattr *band;

    mnl_attr_parse(nlh, sizeof(struct genlmsghdr), eco_iw_nl80211_attr_cb, tb);

    if (!tb[NL80211_ATTR_WIPHY_BANDS])
        return MNL_CB_STOP;

    mnl_attr_for_each_nested(band, tb[NL80211_ATTR_WIPHY_BANDS]) {
        struct nlattr *bands[NL80211_BAND_ATTR_MAX + 1] = {};
        struct nlattr *freq;

        mnl_attr_parse_nested(band, parse_bands_cb, bands);

        if (!bands[NL80211_BAND_ATTR_FREQS])
            continue;

        mnl_attr_for_each_nested(freq, bands[NL80211_BAND_ATTR_FREQS]) {
            struct nlattr *freqs[NL80211_FREQUENCY_ATTR_MAX + 1] = {};
            int mhz;

            mnl_attr_parse_nested(freq, parse_freqs_cb, freqs);

            if (!freqs[NL80211_FREQUENCY_ATTR_FREQ] ||
                freqs[NL80211_FREQUENCY_ATTR_DISABLED])
                continue;

            lua_newtable(co);

            mhz = mnl_attr_get_u32(freqs[NL80211_FREQUENCY_ATTR_FREQ]);

            lua_pushinteger(co, mhz);
            lua_setfield(co, -2, "freq");

            lua_pushinteger(co, ieee80211_freq2channel(mhz));
            lua_setfield(co, -2, "channel");

            if (freqs[NL80211_FREQUENCY_ATTR_NO_IR]) {
                lua_pushboolean(co, true);
                lua_setfield(co, -2, "noir");
            }

            if (freqs[NL80211_FREQUENCY_ATTR_RADAR]) {
                lua_pushboolean(co, true);
                lua_setfield(co, -2, "radar");

                if (freqs[NL80211_FREQUENCY_ATTR_DFS_STATE]) {
                    int state = mnl_attr_get_u32(freqs[NL80211_FREQUENCY_ATTR_DFS_STATE]);
                    switch (state)
                    {
                    case NL80211_DFS_USABLE:
                        lua_pushliteral(co, "usable");
                        break;
                    case NL80211_DFS_UNAVAILABLE:
                        lua_pushliteral(co, "unavailable");
                        break;
                    case NL80211_DFS_AVAILABLE:
                        lua_pushliteral(co, "available");
                        break;
                    default:
                        lua_pushliteral(co, "");
                        break;
                    }
                    lua_setfield(co, -2, "dfs_state");
                }

                if (freqs[NL80211_FREQUENCY_ATTR_DFS_TIME]) {
                    lua_pushinteger(co, mnl_attr_get_u32(freqs[NL80211_FREQUENCY_ATTR_DFS_TIME]));
                    lua_setfield(co, -2, "dfs_time");
                }

                if (freqs[NL80211_FREQUENCY_ATTR_DFS_CAC_TIME]) {
                    lua_pushinteger(co, mnl_attr_get_u32(freqs[NL80211_FREQUENCY_ATTR_DFS_CAC_TIME]));
                    lua_setfield(co, -2, "dfs_cac_time");
                }
            }

            if (freqs[NL80211_FREQUENCY_ATTR_MAX_TX_POWER]) {
                int dbm = mnl_attr_get_u32(freqs[NL80211_FREQUENCY_ATTR_MAX_TX_POWER]) / 100;
                lua_pushinteger(co, dbm);
                lua_setfield(co, -2, "txpower");
            }

            lua_rawseti(co, -2, iw->num++);
        }
    }

    return MNL_CB_STOP;
}

static int eco_iw_freqlist(lua_State *L)
{
    struct eco_iw *iw = lua_touserdata(L, 1);
    int phy = luaL_checkinteger(L, 2);
    struct nlmsghdr *nlh;
    struct genlmsghdr *genl;

    eco_check_context(L);

    nlh = mnl_nlmsg_put_header(iw->buf);
    nlh->nlmsg_type	= iw->family;
    nlh->nlmsg_flags = NLM_F_REQUEST;
    nlh->nlmsg_seq = time(NULL);

    genl = mnl_nlmsg_put_extra_header(nlh, sizeof(struct genlmsghdr));
    genl->cmd = NL80211_CMD_GET_WIPHY;
    genl->version = 1;

    mnl_attr_put_u32(nlh, NL80211_ATTR_WIPHY, phy);

    lua_newtable(L);
    return eco_iw_send(iw, L, nlh, eco_iw_freqlist_cb);
}

struct iw_iso3166_label {
    uint16_t iso3166;
    char name[28];
};

/* ISO3166 country labels */
const struct iw_iso3166_label ISO3166_NAMES[] = {
    { 0x3030 /* 00 */, "World" },
    { 0x4144 /* AD */, "Andorra" },
    { 0x4145 /* AE */, "United Arab Emirates" },
    { 0x4146 /* AF */, "Afghanistan" },
    { 0x4147 /* AG */, "Antigua and Barbuda" },
    { 0x4149 /* AI */, "Anguilla" },
    { 0x414C /* AL */, "Albania" },
    { 0x414D /* AM */, "Armenia" },
    { 0x414E /* AN */, "Netherlands Antilles" },
    { 0x414F /* AO */, "Angola" },
    { 0x4151 /* AQ */, "Antarctica" },
    { 0x4152 /* AR */, "Argentina" },
    { 0x4153 /* AS */, "American Samoa" },
    { 0x4154 /* AT */, "Austria" },
    { 0x4155 /* AU */, "Australia" },
    { 0x4157 /* AW */, "Aruba" },
    { 0x4158 /* AX */, "Aland Islands" },
    { 0x415A /* AZ */, "Azerbaijan" },
    { 0x4241 /* BA */, "Bosnia and Herzegovina" },
    { 0x4242 /* BB */, "Barbados" },
    { 0x4244 /* BD */, "Bangladesh" },
    { 0x4245 /* BE */, "Belgium" },
    { 0x4246 /* BF */, "Burkina Faso" },
    { 0x4247 /* BG */, "Bulgaria" },
    { 0x4248 /* BH */, "Bahrain" },
    { 0x4249 /* BI */, "Burundi" },
    { 0x424A /* BJ */, "Benin" },
    { 0x424C /* BL */, "Saint Barthelemy" },
    { 0x424D /* BM */, "Bermuda" },
    { 0x424E /* BN */, "Brunei Darussalam" },
    { 0x424F /* BO */, "Bolivia" },
    { 0x4252 /* BR */, "Brazil" },
    { 0x4253 /* BS */, "Bahamas" },
    { 0x4254 /* BT */, "Bhutan" },
    { 0x4256 /* BV */, "Bouvet Island" },
    { 0x4257 /* BW */, "Botswana" },
    { 0x4259 /* BY */, "Belarus" },
    { 0x425A /* BZ */, "Belize" },
    { 0x4341 /* CA */, "Canada" },
    { 0x4343 /* CC */, "Cocos (Keeling) Islands" },
    { 0x4344 /* CD */, "Congo" },
    { 0x4346 /* CF */, "Central African Republic" },
    { 0x4347 /* CG */, "Congo" },
    { 0x4348 /* CH */, "Switzerland" },
    { 0x4349 /* CI */, "Cote d'Ivoire" },
    { 0x434B /* CK */, "Cook Islands" },
    { 0x434C /* CL */, "Chile" },
    { 0x434D /* CM */, "Cameroon" },
    { 0x434E /* CN */, "China" },
    { 0x434F /* CO */, "Colombia" },
    { 0x4352 /* CR */, "Costa Rica" },
    { 0x4355 /* CU */, "Cuba" },
    { 0x4356 /* CV */, "Cape Verde" },
    { 0x4358 /* CX */, "Christmas Island" },
    { 0x4359 /* CY */, "Cyprus" },
    { 0x435A /* CZ */, "Czech Republic" },
    { 0x4445 /* DE */, "Germany" },
    { 0x444A /* DJ */, "Djibouti" },
    { 0x444B /* DK */, "Denmark" },
    { 0x444D /* DM */, "Dominica" },
    { 0x444F /* DO */, "Dominican Republic" },
    { 0x445A /* DZ */, "Algeria" },
    { 0x4543 /* EC */, "Ecuador" },
    { 0x4545 /* EE */, "Estonia" },
    { 0x4547 /* EG */, "Egypt" },
    { 0x4548 /* EH */, "Western Sahara" },
    { 0x4552 /* ER */, "Eritrea" },
    { 0x4553 /* ES */, "Spain" },
    { 0x4554 /* ET */, "Ethiopia" },
    { 0x4649 /* FI */, "Finland" },
    { 0x464A /* FJ */, "Fiji" },
    { 0x464B /* FK */, "Falkland Islands" },
    { 0x464D /* FM */, "Micronesia" },
    { 0x464F /* FO */, "Faroe Islands" },
    { 0x4652 /* FR */, "France" },
    { 0x4741 /* GA */, "Gabon" },
    { 0x4742 /* GB */, "United Kingdom" },
    { 0x4744 /* GD */, "Grenada" },
    { 0x4745 /* GE */, "Georgia" },
    { 0x4746 /* GF */, "French Guiana" },
    { 0x4747 /* GG */, "Guernsey" },
    { 0x4748 /* GH */, "Ghana" },
    { 0x4749 /* GI */, "Gibraltar" },
    { 0x474C /* GL */, "Greenland" },
    { 0x474D /* GM */, "Gambia" },
    { 0x474E /* GN */, "Guinea" },
    { 0x4750 /* GP */, "Guadeloupe" },
    { 0x4751 /* GQ */, "Equatorial Guinea" },
    { 0x4752 /* GR */, "Greece" },
    { 0x4753 /* GS */, "South Georgia" },
    { 0x4754 /* GT */, "Guatemala" },
    { 0x4755 /* GU */, "Guam" },
    { 0x4757 /* GW */, "Guinea-Bissau" },
    { 0x4759 /* GY */, "Guyana" },
    { 0x484B /* HK */, "Hong Kong" },
    { 0x484D /* HM */, "Heard and McDonald Islands" },
    { 0x484E /* HN */, "Honduras" },
    { 0x4852 /* HR */, "Croatia" },
    { 0x4854 /* HT */, "Haiti" },
    { 0x4855 /* HU */, "Hungary" },
    { 0x4944 /* ID */, "Indonesia" },
    { 0x4945 /* IE */, "Ireland" },
    { 0x494C /* IL */, "Israel" },
    { 0x494D /* IM */, "Isle of Man" },
    { 0x494E /* IN */, "India" },
    { 0x494F /* IO */, "Chagos Islands" },
    { 0x4951 /* IQ */, "Iraq" },
    { 0x4952 /* IR */, "Iran" },
    { 0x4953 /* IS */, "Iceland" },
    { 0x4954 /* IT */, "Italy" },
    { 0x4A45 /* JE */, "Jersey" },
    { 0x4A4D /* JM */, "Jamaica" },
    { 0x4A4F /* JO */, "Jordan" },
    { 0x4A50 /* JP */, "Japan" },
    { 0x4B45 /* KE */, "Kenya" },
    { 0x4B47 /* KG */, "Kyrgyzstan" },
    { 0x4B48 /* KH */, "Cambodia" },
    { 0x4B49 /* KI */, "Kiribati" },
    { 0x4B4D /* KM */, "Comoros" },
    { 0x4B4E /* KN */, "Saint Kitts and Nevis" },
    { 0x4B50 /* KP */, "North Korea" },
    { 0x4B52 /* KR */, "South Korea" },
    { 0x4B57 /* KW */, "Kuwait" },
    { 0x4B59 /* KY */, "Cayman Islands" },
    { 0x4B5A /* KZ */, "Kazakhstan" },
    { 0x4C41 /* LA */, "Laos" },
    { 0x4C42 /* LB */, "Lebanon" },
    { 0x4C43 /* LC */, "Saint Lucia" },
    { 0x4C49 /* LI */, "Liechtenstein" },
    { 0x4C4B /* LK */, "Sri Lanka" },
    { 0x4C52 /* LR */, "Liberia" },
    { 0x4C53 /* LS */, "Lesotho" },
    { 0x4C54 /* LT */, "Lithuania" },
    { 0x4C55 /* LU */, "Luxembourg" },
    { 0x4C56 /* LV */, "Latvia" },
    { 0x4C59 /* LY */, "Libyan Arab Jamahiriya" },
    { 0x4D41 /* MA */, "Morocco" },
    { 0x4D43 /* MC */, "Monaco" },
    { 0x4D44 /* MD */, "Moldova" },
    { 0x4D45 /* ME */, "Montenegro" },
    { 0x4D46 /* MF */, "Saint Martin (French part)" },
    { 0x4D47 /* MG */, "Madagascar" },
    { 0x4D48 /* MH */, "Marshall Islands" },
    { 0x4D4B /* MK */, "Macedonia" },
    { 0x4D4C /* ML */, "Mali" },
    { 0x4D4D /* MM */, "Myanmar" },
    { 0x4D4E /* MN */, "Mongolia" },
    { 0x4D4F /* MO */, "Macao" },
    { 0x4D50 /* MP */, "Northern Mariana Islands" },
    { 0x4D51 /* MQ */, "Martinique" },
    { 0x4D52 /* MR */, "Mauritania" },
    { 0x4D53 /* MS */, "Montserrat" },
    { 0x4D54 /* MT */, "Malta" },
    { 0x4D55 /* MU */, "Mauritius" },
    { 0x4D56 /* MV */, "Maldives" },
    { 0x4D57 /* MW */, "Malawi" },
    { 0x4D58 /* MX */, "Mexico" },
    { 0x4D59 /* MY */, "Malaysia" },
    { 0x4D5A /* MZ */, "Mozambique" },
    { 0x4E41 /* NA */, "Namibia" },
    { 0x4E43 /* NC */, "New Caledonia" },
    { 0x4E45 /* NE */, "Niger" },
    { 0x4E46 /* NF */, "Norfolk Island" },
    { 0x4E47 /* NG */, "Nigeria" },
    { 0x4E49 /* NI */, "Nicaragua" },
    { 0x4E4C /* NL */, "Netherlands" },
    { 0x4E4F /* NO */, "Norway" },
    { 0x4E50 /* NP */, "Nepal" },
    { 0x4E52 /* NR */, "Nauru" },
    { 0x4E55 /* NU */, "Niue" },
    { 0x4E5A /* NZ */, "New Zealand" },
    { 0x4F4D /* OM */, "Oman" },
    { 0x5041 /* PA */, "Panama" },
    { 0x5045 /* PE */, "Peru" },
    { 0x5046 /* PF */, "French Polynesia" },
    { 0x5047 /* PG */, "Papua New Guinea" },
    { 0x5048 /* PH */, "Philippines" },
    { 0x504B /* PK */, "Pakistan" },
    { 0x504C /* PL */, "Poland" },
    { 0x504D /* PM */, "Saint Pierre and Miquelon" },
    { 0x504E /* PN */, "Pitcairn" },
    { 0x5052 /* PR */, "Puerto Rico" },
    { 0x5053 /* PS */, "Palestinian Territory" },
    { 0x5054 /* PT */, "Portugal" },
    { 0x5057 /* PW */, "Palau" },
    { 0x5059 /* PY */, "Paraguay" },
    { 0x5141 /* QA */, "Qatar" },
    { 0x5245 /* RE */, "Reunion" },
    { 0x524F /* RO */, "Romania" },
    { 0x5253 /* RS */, "Serbia" },
    { 0x5255 /* RU */, "Russian Federation" },
    { 0x5257 /* RW */, "Rwanda" },
    { 0x5341 /* SA */, "Saudi Arabia" },
    { 0x5342 /* SB */, "Solomon Islands" },
    { 0x5343 /* SC */, "Seychelles" },
    { 0x5344 /* SD */, "Sudan" },
    { 0x5345 /* SE */, "Sweden" },
    { 0x5347 /* SG */, "Singapore" },
    { 0x5348 /* SH */, "St. Helena and Dependencies" },
    { 0x5349 /* SI */, "Slovenia" },
    { 0x534A /* SJ */, "Svalbard and Jan Mayen" },
    { 0x534B /* SK */, "Slovakia" },
    { 0x534C /* SL */, "Sierra Leone" },
    { 0x534D /* SM */, "San Marino" },
    { 0x534E /* SN */, "Senegal" },
    { 0x534F /* SO */, "Somalia" },
    { 0x5352 /* SR */, "Suriname" },
    { 0x5354 /* ST */, "Sao Tome and Principe" },
    { 0x5356 /* SV */, "El Salvador" },
    { 0x5359 /* SY */, "Syrian Arab Republic" },
    { 0x535A /* SZ */, "Swaziland" },
    { 0x5443 /* TC */, "Turks and Caicos Islands" },
    { 0x5444 /* TD */, "Chad" },
    { 0x5446 /* TF */, "French Southern Territories" },
    { 0x5447 /* TG */, "Togo" },
    { 0x5448 /* TH */, "Thailand" },
    { 0x544A /* TJ */, "Tajikistan" },
    { 0x544B /* TK */, "Tokelau" },
    { 0x544C /* TL */, "Timor-Leste" },
    { 0x544D /* TM */, "Turkmenistan" },
    { 0x544E /* TN */, "Tunisia" },
    { 0x544F /* TO */, "Tonga" },
    { 0x5452 /* TR */, "Turkey" },
    { 0x5454 /* TT */, "Trinidad and Tobago" },
    { 0x5456 /* TV */, "Tuvalu" },
    { 0x5457 /* TW */, "Taiwan" },
    { 0x545A /* TZ */, "Tanzania" },
    { 0x5541 /* UA */, "Ukraine" },
    { 0x5547 /* UG */, "Uganda" },
    { 0x554D /* UM */, "U.S. Minor Outlying Islands" },
    { 0x5553 /* US */, "United States" },
    { 0x5559 /* UY */, "Uruguay" },
    { 0x555A /* UZ */, "Uzbekistan" },
    { 0x5641 /* VA */, "Vatican City State" },
    { 0x5643 /* VC */, "St. Vincent and Grenadines" },
    { 0x5645 /* VE */, "Venezuela" },
    { 0x5647 /* VG */, "Virgin Islands, British" },
    { 0x5649 /* VI */, "Virgin Islands, U.S." },
    { 0x564E /* VN */, "Viet Nam" },
    { 0x5655 /* VU */, "Vanuatu" },
    { 0x5746 /* WF */, "Wallis and Futuna" },
    { 0x5753 /* WS */, "Samoa" },
    { 0x5945 /* YE */, "Yemen" },
    { 0x5954 /* YT */, "Mayotte" },
    { 0x5A41 /* ZA */, "South Africa" },
    { 0x5A4D /* ZM */, "Zambia" },
    { 0x5A57 /* ZW */, "Zimbabwe" },
    { 0,               "" }
};

static int eco_iw_countrylist(lua_State *L)
{
    const struct iw_iso3166_label *l;
    int i = 1;

    lua_newtable(L);

    for (l = ISO3166_NAMES; l->iso3166; l++) {
        char code[3] = {l->iso3166 / 256, l->iso3166 % 256};

        lua_newtable(L);

        lua_pushstring(L, code);
        lua_setfield(L, -2, "code");

        lua_pushstring(L, l->name);
        lua_setfield(L, -2, "name");

        lua_rawseti(L, -2, i++);
    }

    return 1;
}

static int parse_mc_grps_cb(const struct nlattr *attr, void *data)
{
    const struct nlattr **tb = data;
    int type = mnl_attr_get_type(attr);

    if (type > CTRL_ATTR_MCAST_GRP_MAX)
        return MNL_CB_OK;
    tb[type] = attr;
    return MNL_CB_OK;
}

static void parse_genl_mc_grps(struct eco_iw *iw, struct nlattr *nested)
{
    struct nlattr *pos;

    mnl_attr_for_each_nested(pos, nested) {
        struct nlattr *tb[CTRL_ATTR_MCAST_GRP_MAX+1] = {};

        mnl_attr_parse_nested(pos, parse_mc_grps_cb, tb);
        if (tb[CTRL_ATTR_MCAST_GRP_ID]) {
            iw->event.groups[iw->event.ngroup++] = mnl_attr_get_u32(tb[CTRL_ATTR_MCAST_GRP_ID]);

            if (iw->event.ngroup == ARRAY_SIZE(iw->event.groups))
                break;
        }
    }
}

static int genl_ctl_attr_cb(const struct nlattr *attr, void *data)
{
    const struct nlattr **tb = data;
    int type = mnl_attr_get_type(attr);

    if (type > CTRL_ATTR_MAX)
        return MNL_CB_OK;
    tb[type] = attr;
    return MNL_CB_OK;
}

static int resolve_family_id_cb(const struct nlmsghdr *nlh, void *data)
{
    struct genlmsghdr *genl = mnl_nlmsg_get_payload(nlh);
    struct nlattr *tb[CTRL_ATTR_MAX + 1] = {};
    struct eco_iw *iw = data;

    mnl_attr_parse(nlh, sizeof(*genl), genl_ctl_attr_cb, tb);

    iw->family = mnl_attr_get_u16(tb[CTRL_ATTR_FAMILY_ID]);

    if (tb[CTRL_ATTR_MCAST_GROUPS])
        parse_genl_mc_grps(iw, tb[CTRL_ATTR_MCAST_GROUPS]);

    eco_iw_obj_clean(iw);

    return MNL_CB_STOP;
}

static int eco_iw_new(lua_State *L)
{
    struct eco_context *ctx = eco_check_context(L);
    struct mnl_socket *nl;
    struct nlmsghdr *nlh;
    struct genlmsghdr *genl;
    unsigned int seq;
    struct eco_iw *iw;

    nl = mnl_socket_open2(NETLINK_GENERIC, SOCK_NONBLOCK);
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

    iw = lua_newuserdata(L, sizeof(struct eco_iw) + MNL_SOCKET_BUFFER_SIZE);
    memset(iw, 0, sizeof(struct eco_iw));

    iw->portid = mnl_socket_get_portid(nl);
    iw->ctx = ctx;
    iw->nl = nl;

    lua_pushvalue(L, lua_upvalueindex(1));
    lua_setmetatable(L, -2);

    nlh = mnl_nlmsg_put_header(iw->buf);
    nlh->nlmsg_type	= GENL_ID_CTRL;
    nlh->nlmsg_flags = NLM_F_REQUEST;
    nlh->nlmsg_seq = seq = time(NULL);

    genl = mnl_nlmsg_put_extra_header(nlh, sizeof(struct genlmsghdr));
    genl->cmd = CTRL_CMD_GETFAMILY;
    genl->version = 1;

    mnl_attr_put_u32(nlh, CTRL_ATTR_FAMILY_ID, GENL_ID_CTRL);
    mnl_attr_put_strz(nlh, CTRL_ATTR_FAMILY_NAME, "nl80211");

    if (mnl_socket_sendto(nl, nlh, nlh->nlmsg_len) < 0) {
        lua_pushnil(L);
        lua_pushstring(L, strerror(errno));
        goto err;
    }

    ev_io_init(&iw->io, eco_iw_io_cb, mnl_socket_get_fd(nl), EV_READ);
    ev_init(&iw->tmr, eco_iw_timeout_cb);

    ev_io_start(iw->ctx->loop, &iw->io);

    iw->co = L;
    iw->seq = seq;
    iw->cb = resolve_family_id_cb;

    lua_pushlightuserdata(L, &eco_iw_obj_key);
    lua_rawget(L, LUA_REGISTRYINDEX);   /* userdata, table */
    lua_pushlightuserdata(L, iw);       /* userdata, table, key */
    lua_pushvalue(L, -3);               /* userdata, table, key, userdata */
    lua_rawset(L, -3);                  /* userdata, table */
    lua_pop(L, 2);

    return lua_yield(L, 0);

err:
    mnl_socket_close(nl);
    return 2;
}

static const struct luaL_Reg iw_metatable[] =  {
    {"__gc", eco_iw_gc},
    {"close", eco_iw_gc},
    {"add_interface", eco_iw_add_interface},
    {"del_interface", eco_iw_del_interface},
    {"info", eco_iw_devinfo},
    {"wait", eco_iw_wait},
    {"scan_trigger", eco_iw_scan_trigger},
    {"scan_dump", eco_iw_scan_dump},
    {"assoclist", eco_iw_assoclist},
    {"freqlist", eco_iw_freqlist},
    {"countrylist", eco_iw_countrylist},
    {NULL, NULL}
};

int luaopen_eco_iw(lua_State *L)
{
    lua_pushlightuserdata(L, &eco_iw_obj_key);
    lua_newtable(L);
    lua_rawset(L, LUA_REGISTRYINDEX);
    lua_pop(L, 1);

    lua_newtable(L);

    lua_add_constant("NEW_WIPHY", NL80211_CMD_NEW_WIPHY);
    lua_add_constant("DEL_WIPHY", NL80211_CMD_DEL_WIPHY);
    lua_add_constant("NEW_INTERFACE", NL80211_CMD_NEW_INTERFACE);
    lua_add_constant("DEL_INTERFACE", NL80211_CMD_DEL_INTERFACE);
    lua_add_constant("NEW_STATION", NL80211_CMD_NEW_STATION);
    lua_add_constant("DEL_STATION", NL80211_CMD_DEL_STATION);
    lua_add_constant("NEW_SCAN_RESULTS", NL80211_CMD_NEW_SCAN_RESULTS);
    lua_add_constant("SCAN_ABORTED", NL80211_CMD_SCAN_ABORTED);
    lua_add_constant("AUTHENTICATE", NL80211_CMD_AUTHENTICATE);
    lua_add_constant("ASSOCIATE", NL80211_CMD_ASSOCIATE);
    lua_add_constant("DEAUTHENTICATE", NL80211_CMD_DEAUTHENTICATE);
    lua_add_constant("DISASSOCIATE", NL80211_CMD_DISASSOCIATE);
    lua_add_constant("DISCONNECT", NL80211_CMD_DISCONNECT);
    lua_add_constant("NEW_SURVEY_RESULTS", NL80211_CMD_NEW_SURVEY_RESULTS);
    lua_add_constant("START_SCHED_SCAN", NL80211_CMD_START_SCHED_SCAN);
    lua_add_constant("SCHED_SCAN_RESULTS", NL80211_CMD_SCHED_SCAN_RESULTS);
    lua_add_constant("SCHED_SCAN_STOPPED", NL80211_CMD_SCHED_SCAN_STOPPED);
    lua_add_constant("PROBE_CLIENT", NL80211_CMD_PROBE_CLIENT);
    lua_add_constant("CH_SWITCH_NOTIFY", NL80211_CMD_CH_SWITCH_NOTIFY);
    lua_add_constant("CONN_FAILED", NL80211_CMD_CONN_FAILED);
    lua_add_constant("RADAR_DETECT", NL80211_CMD_RADAR_DETECT);
    lua_add_constant("CH_SWITCH_STARTED_NOTIFY", NL80211_CMD_CH_SWITCH_STARTED_NOTIFY);
    lua_add_constant("WIPHY_REG_CHANGE", NL80211_CMD_WIPHY_REG_CHANGE);
    lua_add_constant("ABORT_SCAN", NL80211_CMD_ABORT_SCAN);
    lua_add_constant("NOTIFY_RADAR", NL80211_CMD_NOTIFY_RADAR);

    eco_new_metatable(L, iw_metatable);
    lua_pushcclosure(L, eco_iw_new, 1);
    lua_setfield(L, -2, "new");

    return 1;
}
