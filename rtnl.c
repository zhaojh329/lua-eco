/* SPDX-License-Identifier: MIT */
/*
 * Author: Jianhui Zhao <zhaojh329@gmail.com>
 */

#include <linux/rtnetlink.h>
#include <linux/if.h>

#include "nl.h"

static int eco_rtnl_new_rtgenmsg(lua_State *L)
{
    struct rtgenmsg m = {};

    luaL_checktype(L, 1, LUA_TTABLE);

    lua_getfield(L, 1, "family");
    m.rtgen_family = lua_tointeger(L, -1);

    lua_pushlstring(L, (const char *)&m, sizeof(m));
    return 1;
}

static int eco_rtnl_new_ifinfomsg(lua_State *L)
{
    struct ifinfomsg ifm = {};

    luaL_checktype(L, 1, LUA_TTABLE);

    lua_getfield(L, 1, "family");
    ifm.ifi_family = lua_tointeger(L, -1);

    lua_getfield(L, 1, "type");
    ifm.ifi_type = lua_tointeger(L, -1);

    lua_getfield(L, 1, "index");
    ifm.ifi_index = lua_tointeger(L, -1);

    lua_getfield(L, 1, "flags");
    ifm.ifi_flags = lua_tointeger(L, -1);

    lua_getfield(L, 1, "change");
    ifm.ifi_change = lua_tointeger(L, -1);

    lua_pushlstring(L, (const char *)&ifm, sizeof(ifm));
    return 1;
}

static int eco_rtnl_new_ifaddrmsg(lua_State *L)
{
    struct ifaddrmsg ifm = {};

    luaL_checktype(L, 1, LUA_TTABLE);

    lua_getfield(L, 1, "family");
    ifm.ifa_family = lua_tointeger(L, -1);

    lua_getfield(L, 1, "prefixlen");
    ifm.ifa_prefixlen = lua_tointeger(L, -1);

    lua_getfield(L, 1, "flags");
    ifm.ifa_flags = lua_tointeger(L, -1);

    lua_getfield(L, 1, "scope");
    ifm.ifa_scope = lua_tointeger(L, -1);

    lua_getfield(L, 1, "index");
    ifm.ifa_index = lua_tointeger(L, -1);

    lua_pushlstring(L, (const char *)&ifm, sizeof(ifm));
    return 1;
}

static int eco_rtnl_parse_ifinfomsg(lua_State *L)
{
    struct eco_nlmsg *msg = luaL_checkudata(L, 1, ECO_NLMSG_KER_MT);
    struct nlmsghdr *nlh = msg->nlh;
    struct ifinfomsg *ifm;

    if (!NLMSG_OK(nlh, msg->size)) {
        lua_pushnil(L);
        lua_pushliteral(L, "invalid nlmsg");
        return 2;
    }

    if (nlh->nlmsg_type != RTM_NEWLINK && nlh->nlmsg_type != RTM_DELLINK) {
        lua_pushnil(L);
        lua_pushliteral(L, "invalid nlmsg type");
        return 2;
    }

	ifm = NLMSG_DATA(nlh);

    lua_newtable(L);

    lua_pushinteger(L, ifm->ifi_family);
    lua_setfield(L, -2, "family");

    lua_pushinteger(L, ifm->ifi_type);
    lua_setfield(L, -2, "type");

    lua_pushinteger(L, ifm->ifi_index);
    lua_setfield(L, -2, "index");

    lua_pushinteger(L, ifm->ifi_flags);
    lua_setfield(L, -2, "flags");

    lua_pushinteger(L, ifm->ifi_change);
    lua_setfield(L, -2, "change");

    return 1;
}

static int eco_rtnl_parse_ifaddrmsg(lua_State *L)
{
    struct eco_nlmsg *msg = luaL_checkudata(L, 1, ECO_NLMSG_KER_MT);
    struct nlmsghdr *nlh = msg->nlh;
    struct ifaddrmsg *ifm;

    if (!NLMSG_OK(nlh, msg->size)) {
        lua_pushnil(L);
        lua_pushliteral(L, "invalid nlmsg");
        return 2;
    }

    if (nlh->nlmsg_type != RTM_NEWADDR) {
        lua_pushnil(L);
        lua_pushliteral(L, "invalid nlmsg type");
        return 2;
    }

	ifm = NLMSG_DATA(nlh);

    lua_newtable(L);

    lua_pushinteger(L, ifm->ifa_family);
    lua_setfield(L, -2, "family");

    lua_pushinteger(L, ifm->ifa_prefixlen);
    lua_setfield(L, -2, "prefixlen");

    lua_pushinteger(L, ifm->ifa_flags);
    lua_setfield(L, -2, "flags");

    lua_pushinteger(L, ifm->ifa_scope);
    lua_setfield(L, -2, "scope");

    lua_pushinteger(L, ifm->ifa_index);
    lua_setfield(L, -2, "index");

    return 1;
}

int luaopen_eco_rtnl(lua_State *L)
{
    lua_newtable(L);

    lua_add_constant(L, "RTM_NEWLINK", RTM_NEWLINK);
    lua_add_constant(L, "RTM_DELLINK", RTM_DELLINK);
    lua_add_constant(L, "RTM_GETLINK", RTM_GETLINK);
    lua_add_constant(L, "RTM_SETLINK", RTM_SETLINK);
    lua_add_constant(L, "RTM_NEWADDR", RTM_NEWADDR);
    lua_add_constant(L, "RTM_DELADDR", RTM_DELADDR);
    lua_add_constant(L, "RTM_GETADDR", RTM_GETADDR);
    lua_add_constant(L, "RTM_NEWROUTE", RTM_NEWROUTE);
    lua_add_constant(L, "RTM_DELROUTE", RTM_DELROUTE);
    lua_add_constant(L, "RTM_GETROUTE", RTM_GETROUTE);
    lua_add_constant(L, "RTM_NEWNEIGH", RTM_NEWNEIGH);
    lua_add_constant(L, "RTM_DELNEIGH", RTM_DELNEIGH);
    lua_add_constant(L, "RTM_GETNEIGH", RTM_GETNEIGH);
    lua_add_constant(L, "RTM_NEWRULE", RTM_NEWRULE);
    lua_add_constant(L, "RTM_DELRULE", RTM_DELRULE);
    lua_add_constant(L, "RTM_GETRULE", RTM_GETRULE);
    lua_add_constant(L, "RTM_NEWQDISC", RTM_NEWQDISC);
    lua_add_constant(L, "RTM_DELQDISC", RTM_DELQDISC);
    lua_add_constant(L, "RTM_GETQDISC", RTM_GETQDISC);
    lua_add_constant(L, "RTM_NEWTCLASS", RTM_NEWTCLASS);
    lua_add_constant(L, "RTM_DELTCLASS", RTM_DELTCLASS);
    lua_add_constant(L, "RTM_GETTCLASS", RTM_GETTCLASS);
    lua_add_constant(L, "RTM_NEWTFILTER", RTM_NEWTFILTER);
    lua_add_constant(L, "RTM_DELTFILTER", RTM_DELTFILTER);
    lua_add_constant(L, "RTM_GETTFILTER", RTM_GETTFILTER);
    lua_add_constant(L, "RTM_NEWACTION", RTM_NEWACTION);
    lua_add_constant(L, "RTM_DELACTION", RTM_DELACTION);
    lua_add_constant(L, "RTM_GETACTION", RTM_GETACTION);
    lua_add_constant(L, "RTM_NEWPREFIX", RTM_NEWPREFIX);
    lua_add_constant(L, "RTM_GETMULTICAST", RTM_GETMULTICAST);
    lua_add_constant(L, "RTM_GETANYCAST", RTM_GETANYCAST);
    lua_add_constant(L, "RTM_NEWNEIGHTBL", RTM_NEWNEIGHTBL);
    lua_add_constant(L, "RTM_GETNEIGHTBL", RTM_GETNEIGHTBL);
    lua_add_constant(L, "RTM_SETNEIGHTBL", RTM_SETNEIGHTBL);
    lua_add_constant(L, "RTM_NEWNDUSEROPT", RTM_NEWNDUSEROPT);
    lua_add_constant(L, "RTM_NEWADDRLABEL", RTM_NEWADDRLABEL);
    lua_add_constant(L, "RTM_DELADDRLABEL", RTM_DELADDRLABEL);
    lua_add_constant(L, "RTM_GETADDRLABEL", RTM_GETADDRLABEL);
    lua_add_constant(L, "RTM_GETDCB", RTM_GETDCB);
    lua_add_constant(L, "RTM_SETDCB", RTM_SETDCB);
    lua_add_constant(L, "RTM_NEWNETCONF", RTM_NEWNETCONF);
    lua_add_constant(L, "RTM_DELNETCONF", RTM_DELNETCONF);
    lua_add_constant(L, "RTM_GETNETCONF", RTM_GETNETCONF);
    lua_add_constant(L, "RTM_NEWMDB", RTM_NEWMDB);
    lua_add_constant(L, "RTM_DELMDB", RTM_DELMDB);
    lua_add_constant(L, "RTM_GETMDB", RTM_GETMDB);
    lua_add_constant(L, "RTM_NEWNSID", RTM_NEWNSID);
    lua_add_constant(L, "RTM_DELNSID", RTM_DELNSID);
    lua_add_constant(L, "RTM_GETNSID", RTM_GETNSID);
    lua_add_constant(L, "RTM_NEWSTATS", RTM_NEWSTATS);
    lua_add_constant(L, "RTM_GETSTATS", RTM_GETSTATS);
    lua_add_constant(L, "RTM_NEWCACHEREPORT", RTM_NEWCACHEREPORT);
    lua_add_constant(L, "RTM_NEWCHAIN", RTM_NEWCHAIN);
    lua_add_constant(L, "RTM_DELCHAIN", RTM_DELCHAIN);
    lua_add_constant(L, "RTM_GETCHAIN", RTM_GETCHAIN);
    lua_add_constant(L, "RTM_NEWNEXTHOP", RTM_NEWNEXTHOP);
    lua_add_constant(L, "RTM_DELNEXTHOP", RTM_DELNEXTHOP);
    lua_add_constant(L, "RTM_GETNEXTHOP", RTM_GETNEXTHOP);
    lua_add_constant(L, "RTM_NEWLINKPROP", RTM_NEWLINKPROP);
    lua_add_constant(L, "RTM_DELLINKPROP", RTM_DELLINKPROP);
    lua_add_constant(L, "RTM_GETLINKPROP", RTM_GETLINKPROP);
    lua_add_constant(L, "RTM_NEWVLAN", RTM_NEWVLAN);
    lua_add_constant(L, "RTM_DELVLAN", RTM_DELVLAN);
    lua_add_constant(L, "RTM_GETVLAN", RTM_GETVLAN);

    lua_add_constant(L, "IFF_UP", IFF_UP);
    lua_add_constant(L, "IFF_BROADCAST", IFF_BROADCAST);
    lua_add_constant(L, "IFF_DEBUG", IFF_DEBUG);
    lua_add_constant(L, "IFF_LOOPBACK", IFF_LOOPBACK);
    lua_add_constant(L, "IFF_POINTOPOINT", IFF_POINTOPOINT);
    lua_add_constant(L, "IFF_NOTRAILERS", IFF_NOTRAILERS);
    lua_add_constant(L, "IFF_RUNNING", IFF_RUNNING);
    lua_add_constant(L, "IFF_NOARP", IFF_NOARP);
    lua_add_constant(L, "IFF_PROMISC", IFF_PROMISC);
    lua_add_constant(L, "IFF_ALLMULTI", IFF_ALLMULTI);
    lua_add_constant(L, "IFF_MASTER", IFF_MASTER);
    lua_add_constant(L, "IFF_SLAVE", IFF_SLAVE);
    lua_add_constant(L, "IFF_MULTICAST", IFF_MULTICAST);
    lua_add_constant(L, "IFF_PORTSEL", IFF_PORTSEL);
    lua_add_constant(L, "IFF_AUTOMEDIA", IFF_AUTOMEDIA);
    lua_add_constant(L, "IFF_DYNAMIC", IFF_DYNAMIC);

    lua_add_constant(L, "IFLA_UNSPEC", IFLA_UNSPEC);
    lua_add_constant(L, "IFLA_ADDRESS", IFLA_ADDRESS);
    lua_add_constant(L, "IFLA_BROADCAST", IFLA_BROADCAST);
    lua_add_constant(L, "IFLA_IFNAME", IFLA_IFNAME);
    lua_add_constant(L, "IFLA_MTU", IFLA_MTU);
    lua_add_constant(L, "IFLA_LINK", IFLA_LINK);
    lua_add_constant(L, "IFLA_QDISC", IFLA_QDISC);
    lua_add_constant(L, "IFLA_STATS", IFLA_STATS);
    lua_add_constant(L, "IFLA_COST", IFLA_COST);
    lua_add_constant(L, "IFLA_PRIORITY", IFLA_PRIORITY);
    lua_add_constant(L, "IFLA_MASTER", IFLA_MASTER);
    lua_add_constant(L, "IFLA_WIRELESS", IFLA_WIRELESS);
    lua_add_constant(L, "IFLA_PROTINFO", IFLA_PROTINFO);
    lua_add_constant(L, "IFLA_TXQLEN", IFLA_TXQLEN);
    lua_add_constant(L, "IFLA_MAP", IFLA_MAP);
    lua_add_constant(L, "IFLA_WEIGHT", IFLA_WEIGHT);
    lua_add_constant(L, "IFLA_OPERSTATE", IFLA_OPERSTATE);
    lua_add_constant(L, "IFLA_LINKMODE", IFLA_LINKMODE);
    lua_add_constant(L, "IFLA_LINKINFO", IFLA_LINKINFO);
    lua_add_constant(L, "IFLA_NET_NS_PID", IFLA_NET_NS_PID);
    lua_add_constant(L, "IFLA_IFALIAS", IFLA_IFALIAS);
    lua_add_constant(L, "IFLA_NUM_VF	", IFLA_NUM_VF	);
    lua_add_constant(L, "IFLA_VFINFO_LIST", IFLA_VFINFO_LIST);
    lua_add_constant(L, "IFLA_STATS64", IFLA_STATS64);
    lua_add_constant(L, "IFLA_VF_PORTS", IFLA_VF_PORTS);
    lua_add_constant(L, "IFLA_PORT_SELF", IFLA_PORT_SELF);
    lua_add_constant(L, "IFLA_AF_SPEC", IFLA_AF_SPEC);
    lua_add_constant(L, "IFLA_GROUP	", IFLA_GROUP	);
    lua_add_constant(L, "IFLA_NET_NS_FD", IFLA_NET_NS_FD);
    lua_add_constant(L, "IFLA_EXT_MASK	", IFLA_EXT_MASK	);
    lua_add_constant(L, "IFLA_PROMISCUITY", IFLA_PROMISCUITY);
    lua_add_constant(L, "IFLA_NUM_TX_QUEUES", IFLA_NUM_TX_QUEUES);
    lua_add_constant(L, "IFLA_NUM_RX_QUEUES", IFLA_NUM_RX_QUEUES);
    lua_add_constant(L, "IFLA_CARRIER", IFLA_CARRIER);
    lua_add_constant(L, "IFLA_PHYS_PORT_ID", IFLA_PHYS_PORT_ID);
    lua_add_constant(L, "IFLA_CARRIER_CHANGES", IFLA_CARRIER_CHANGES);
    lua_add_constant(L, "IFLA_PHYS_SWITCH_ID", IFLA_PHYS_SWITCH_ID);
    lua_add_constant(L, "IFLA_LINK_NETNSID", IFLA_LINK_NETNSID);
    lua_add_constant(L, "IFLA_PHYS_PORT_NAME", IFLA_PHYS_PORT_NAME);
    lua_add_constant(L, "IFLA_PROTO_DOWN", IFLA_PROTO_DOWN);
    lua_add_constant(L, "IFLA_GSO_MAX_SEGS", IFLA_GSO_MAX_SEGS);
    lua_add_constant(L, "IFLA_GSO_MAX_SIZE", IFLA_GSO_MAX_SIZE);
    lua_add_constant(L, "IFLA_PAD", IFLA_PAD);
    lua_add_constant(L, "IFLA_XDP", IFLA_XDP);
    lua_add_constant(L, "IFLA_EVENT", IFLA_EVENT);
    lua_add_constant(L, "IFLA_NEW_NETNSID", IFLA_NEW_NETNSID);
    lua_add_constant(L, "IFLA_IF_NETNSID", IFLA_IF_NETNSID);
    lua_add_constant(L, "IFLA_CARRIER_UP_COUNT", IFLA_CARRIER_UP_COUNT);
    lua_add_constant(L, "IFLA_CARRIER_DOWN_COUNT", IFLA_CARRIER_DOWN_COUNT);
    lua_add_constant(L, "IFLA_NEW_IFINDEX", IFLA_NEW_IFINDEX);
    lua_add_constant(L, "IFLA_MIN_MTU", IFLA_MIN_MTU);
    lua_add_constant(L, "IFLA_MAX_MTU", IFLA_MAX_MTU);
    lua_add_constant(L, "IFLA_PROP_LIST", IFLA_PROP_LIST);
    lua_add_constant(L, "IFLA_ALT_IFNAME", IFLA_ALT_IFNAME);
    lua_add_constant(L, "IFLA_PERM_ADDRESS", IFLA_PERM_ADDRESS);
    lua_add_constant(L, "IFLA_PROTO_DOWN_REASON", IFLA_PROTO_DOWN_REASON);

    lua_add_constant(L, "IFA_UNSPEC", IFA_UNSPEC);
    lua_add_constant(L, "IFA_ADDRESS", IFA_ADDRESS);
    lua_add_constant(L, "IFA_LOCAL", IFA_LOCAL);
    lua_add_constant(L, "IFA_LABEL", IFA_LABEL);
    lua_add_constant(L, "IFA_BROADCAST", IFA_BROADCAST);
    lua_add_constant(L, "IFA_ANYCAST", IFA_ANYCAST);
    lua_add_constant(L, "IFA_CACHEINFO", IFA_CACHEINFO);
    lua_add_constant(L, "IFA_MULTICAST", IFA_MULTICAST);
    lua_add_constant(L, "IFA_FLAGS", IFA_FLAGS);
    lua_add_constant(L, "IFA_RT_PRIORITY", IFA_RT_PRIORITY);
    lua_add_constant(L, "IFA_TARGET_NETNSID", IFA_TARGET_NETNSID);

    lua_add_constant(L, "RTNLGRP_LINK", RTNLGRP_LINK);
    lua_add_constant(L, "RTNLGRP_NOTIFY", RTNLGRP_NOTIFY);
    lua_add_constant(L, "RTNLGRP_NEIGH", RTNLGRP_NEIGH);
    lua_add_constant(L, "RTNLGRP_TC", RTNLGRP_TC);
    lua_add_constant(L, "RTNLGRP_IPV4_IFADDR", RTNLGRP_IPV4_IFADDR);
    lua_add_constant(L, "RTNLGRP_IPV4_MROUTE", RTNLGRP_IPV4_MROUTE);
    lua_add_constant(L, "RTNLGRP_IPV4_ROUTE", RTNLGRP_IPV4_ROUTE);
    lua_add_constant(L, "RTNLGRP_IPV4_RULE", RTNLGRP_IPV4_RULE);
    lua_add_constant(L, "RTNLGRP_IPV6_IFADDR", RTNLGRP_IPV6_IFADDR);
    lua_add_constant(L, "RTNLGRP_IPV6_MROUTE", RTNLGRP_IPV6_MROUTE);
    lua_add_constant(L, "RTNLGRP_IPV6_ROUTE", RTNLGRP_IPV6_ROUTE);
    lua_add_constant(L, "RTNLGRP_IPV6_IFINFO", RTNLGRP_IPV6_IFINFO);
    lua_add_constant(L, "RTNLGRP_DECnet_IFADDR", RTNLGRP_DECnet_IFADDR);
    lua_add_constant(L, "RTNLGRP_NOP2", RTNLGRP_NOP2);
    lua_add_constant(L, "RTNLGRP_DECnet_ROUTE", RTNLGRP_DECnet_ROUTE);
    lua_add_constant(L, "RTNLGRP_DECnet_RULE", RTNLGRP_DECnet_RULE);
    lua_add_constant(L, "RTNLGRP_NOP4", RTNLGRP_NOP4);
    lua_add_constant(L, "RTNLGRP_IPV6_PREFIX", RTNLGRP_IPV6_PREFIX);
    lua_add_constant(L, "RTNLGRP_IPV6_RULE", RTNLGRP_IPV6_RULE);
    lua_add_constant(L, "RTNLGRP_ND_USEROPT", RTNLGRP_ND_USEROPT);
    lua_add_constant(L, "RTNLGRP_PHONET_IFADDR", RTNLGRP_PHONET_IFADDR);
    lua_add_constant(L, "RTNLGRP_PHONET_ROUTE", RTNLGRP_PHONET_ROUTE);
    lua_add_constant(L, "RTNLGRP_DCB", RTNLGRP_DCB);
    lua_add_constant(L, "RTNLGRP_IPV4_NETCONF", RTNLGRP_IPV4_NETCONF);
    lua_add_constant(L, "RTNLGRP_IPV6_NETCONF", RTNLGRP_IPV6_NETCONF);
    lua_add_constant(L, "RTNLGRP_MDB", RTNLGRP_MDB);
    lua_add_constant(L, "RTNLGRP_MPLS_ROUTE", RTNLGRP_MPLS_ROUTE);
    lua_add_constant(L, "RTNLGRP_NSID", RTNLGRP_NSID);
    lua_add_constant(L, "RTNLGRP_MPLS_NETCONF", RTNLGRP_MPLS_NETCONF);
    lua_add_constant(L, "RTNLGRP_IPV4_MROUTE_R", RTNLGRP_IPV4_MROUTE_R);
    lua_add_constant(L, "RTNLGRP_IPV6_MROUTE_R", RTNLGRP_IPV6_MROUTE_R);
    lua_add_constant(L, "RTNLGRP_NEXTHOP", RTNLGRP_NEXTHOP);
    lua_add_constant(L, "RTNLGRP_BRVLAN", RTNLGRP_BRVLAN);

    lua_add_constant(L, "IFINFOMSG_SIZE", sizeof(struct ifinfomsg));
    lua_add_constant(L, "IFADDRMSG_SIZE", sizeof(struct ifaddrmsg));

    lua_pushcfunction(L, eco_rtnl_new_rtgenmsg);
    lua_setfield(L, -2, "rtgenmsg");

    lua_pushcfunction(L, eco_rtnl_new_ifinfomsg);
    lua_setfield(L, -2, "ifinfomsg");

    lua_pushcfunction(L, eco_rtnl_new_ifaddrmsg);
    lua_setfield(L, -2, "ifaddrmsg");

    lua_pushcfunction(L, eco_rtnl_parse_ifinfomsg);
    lua_setfield(L, -2, "parse_ifinfomsg");

    lua_pushcfunction(L, eco_rtnl_parse_ifaddrmsg);
    lua_setfield(L, -2, "parse_ifaddrmsg");

    return 1;
}
