/* SPDX-License-Identifier: MIT */
/*
 * Author: Jianhui Zhao <zhaojh329@gmail.com>
 */

#include <string.h>
#include <errno.h>

#include "nl.h"

#define NLMSG_USER_MT "struct eco_nlmsg *usr"

static int eco_nlmsg_next(lua_State *L)
{
    struct eco_nlmsg *msg = luaL_checkudata(L, 1, NLMSG_KER_MT);
    struct nlmsghdr *nlh;

    if (!msg->nlh) {
        msg->nlh = (struct nlmsghdr *)msg->buf;
    } else {
        if (!NLMSG_OK(msg->nlh, msg->size)) {
            lua_pushnil(L);
            return 1;
        }
        msg->nlh = NLMSG_NEXT(msg->nlh, msg->size);
    }

    nlh = msg->nlh;

    if (!NLMSG_OK(nlh, msg->size)) {
        lua_pushnil(L);
        return 1;
    }

    lua_newtable(L);

    lua_pushinteger(L, nlh->nlmsg_type);
    lua_setfield(L, -2, "type");

    lua_pushinteger(L, nlh->nlmsg_flags);
    lua_setfield(L, -2, "flags");

    lua_pushinteger(L, nlh->nlmsg_seq);
    lua_setfield(L, -2, "seq");

    lua_pushinteger(L, nlh->nlmsg_pid);
    lua_setfield(L, -2, "pid");

    return 1;
}

static int eco_nlmsg_payload(lua_State *L)
{
    struct eco_nlmsg *msg = luaL_checkudata(L, 1, NLMSG_KER_MT);
    struct nlmsghdr *nlh = msg->nlh;

    if (!NLMSG_OK(nlh, msg->size)) {
        lua_pushnil(L);
        lua_pushliteral(L, "invalid nlmsg");
        return 2;
    }

    lua_pushlstring(L, NLMSG_DATA(nlh), NLMSG_PAYLOAD(nlh, 0));
    return 1;
}

static int eco_nlmsg_parse_attr(lua_State *L)
{
    struct eco_nlmsg *msg = luaL_checkudata(L, 1, NLMSG_KER_MT);
    size_t offset = luaL_checkinteger(L, 2);
    struct nlmsghdr *nlh = msg->nlh;
	const struct nlattr *attr;
    int rem;

    if (!NLMSG_OK(nlh, msg->size)) {
        lua_pushnil(L);
        lua_pushliteral(L, "invalid nlmsg");
        return 2;
    }

    lua_newtable(L);

    nla_for_each_attr(attr, NLMSG_DATA(nlh) + NLMSG_ALIGN(offset), NLMSG_PAYLOAD(nlh, offset), rem) {
        lua_pushlstring(L, (const char *)attr, attr->nla_len);
        lua_rawseti(L, -2, nla_type(attr));
    }

    return 1;
}

static int eco_nlmsg_parse_error(lua_State *L)
{
    struct eco_nlmsg *msg = luaL_checkudata(L, 1, NLMSG_KER_MT);
    struct nlmsghdr *nlh = msg->nlh;
	struct nlmsgerr *err;

    if (!NLMSG_OK(nlh, msg->size)) {
        lua_pushnil(L);
        lua_pushliteral(L, "invalid nlmsg");
        return 2;
    }

    if (nlh->nlmsg_type != NLMSG_ERROR) {
        lua_pushnil(L);
        lua_pushliteral(L, "not a nlmsg with type NLMSG_ERROR");
        return 2;
    }

    if (nlh->nlmsg_len < NLMSG_LENGTH(sizeof(struct nlmsgerr))) {
		lua_pushnil(L);
        lua_pushliteral(L, "invalid nlmsg");
        return 2;
	}

    err = NLMSG_DATA(nlh);

    lua_pushinteger(L, err->error);
    return 1;
}

static const struct luaL_Reg nlmsg_ker_methods[] =  {
    {"next", eco_nlmsg_next},
    {"payload", eco_nlmsg_payload},
    {"parse_attr", eco_nlmsg_parse_attr},
    {"parse_error", eco_nlmsg_parse_error},
    {NULL, NULL}
};

static int lua_new_nlmsg_ker(lua_State *L)
{
    size_t len;
    const char *data = luaL_checklstring(L, 1, &len);
    struct eco_nlmsg *msg;

    msg = lua_newuserdata(L, sizeof(struct eco_nlmsg) + len);
    luaL_setmetatable(L, NLMSG_KER_MT);

    memcpy(msg->buf, data, len);

    msg->size = len;
    msg->nlh = NULL;
    msg->nest = NULL;

    return 1;
}

static int eco_nlmsg_to_binary(lua_State *L)
{
    struct eco_nlmsg *msg = luaL_checkudata(L, 1, NLMSG_USER_MT);
    lua_pushlstring(L, (const char *)msg->buf, msg->nlh->nlmsg_len);
    return 1;
}

static int eco_nlmsg_put(lua_State *L)
{
    struct eco_nlmsg *msg = luaL_checkudata(L, 1, NLMSG_USER_MT);
    struct nlmsghdr *nlh = msg->nlh;
    size_t len;
    const char *data = luaL_checklstring(L, 2, &len);

    if (nlh->nlmsg_len + NLMSG_ALIGN(len) > msg->size) {
        lua_pushnil(L);
        lua_pushliteral(L, "buf is full");
		return 2;
    }

    memcpy((char *)msg->nlh + nlh->nlmsg_len, data, len);

	nlh->nlmsg_len += NLMSG_ALIGN(len);

	lua_settop(L, 1);
    return 1;
}

static int __eco_nlmsg_put_attr(lua_State *L, struct eco_nlmsg *msg,
        uint16_t type, size_t len, const void *data)
{
    struct nlmsghdr *nlh = msg->nlh;
	struct nlattr *attr = (void *)nlh + NLMSG_ALIGN(nlh->nlmsg_len);
	uint16_t payload_len = NLMSG_ALIGN(sizeof(struct nlattr)) + len;
	int pad;

    if (nlh->nlmsg_len + NLA_HDRLEN + NLMSG_ALIGN(len) > msg->size) {
        lua_pushnil(L);
        lua_pushliteral(L, "buf is full");
		return 2;
    }

	attr->nla_type = type;
	attr->nla_len = payload_len;
	memcpy(nla_data(attr), data, len);

	pad = NLMSG_ALIGN(len) - len;
	if (pad > 0)
		memset(nla_data(attr) + len, 0, pad);

	nlh->nlmsg_len += NLMSG_ALIGN(payload_len);

    if (type & NLA_F_NESTED)
        msg->nest = attr;
    else if (msg->nest)
        msg->nest->nla_len += NLMSG_ALIGN(payload_len);

    lua_settop(L, 1);

    return 1;
}

static int eco_nlmsg_put_attr(lua_State *L)
{
    struct eco_nlmsg *msg = luaL_checkudata(L, 1, NLMSG_USER_MT);
    int type = luaL_checkinteger(L, 2);
    size_t len;
    const char *value = luaL_checklstring(L, 3, &len);

    return __eco_nlmsg_put_attr(L, msg, type, len, value);
}

static int eco_nlmsg_put_attr_flag(lua_State *L)
{
    struct eco_nlmsg *msg = luaL_checkudata(L, 1, NLMSG_USER_MT);
    int type = luaL_checkinteger(L, 2);

    return __eco_nlmsg_put_attr(L, msg, type, 0, NULL);
}

static int eco_nlmsg_put_attr_u8(lua_State *L)
{
    struct eco_nlmsg *msg = luaL_checkudata(L, 1, NLMSG_USER_MT);
    int type = luaL_checkinteger(L, 2);
    int value = luaL_checkinteger(L, 3);

    return __eco_nlmsg_put_attr(L, msg, type, sizeof(uint8_t), &value);
}

static int eco_nlmsg_put_attr_u16(lua_State *L)
{
    struct eco_nlmsg *msg = luaL_checkudata(L, 1, NLMSG_USER_MT);
    int type = luaL_checkinteger(L, 2);
    int value = luaL_checkinteger(L, 3);

    return __eco_nlmsg_put_attr(L, msg, type, sizeof(uint16_t), &value);
}

static int eco_nlmsg_put_attr_u32(lua_State *L)
{
    struct eco_nlmsg *msg = luaL_checkudata(L, 1, NLMSG_USER_MT);
    int type = luaL_checkinteger(L, 2);
    uint32_t value;

    if (sizeof(lua_Integer) < 8)
        value = (uint32_t)luaL_checknumber(L, 3);
    else
        value = (uint32_t)luaL_checkinteger(L, 3);

    return __eco_nlmsg_put_attr(L, msg, type, sizeof(uint32_t), &value);
}

static int eco_nlmsg_put_attr_u64(lua_State *L)
{
    struct eco_nlmsg *msg = luaL_checkudata(L, 1, NLMSG_USER_MT);
    int type = luaL_checkinteger(L, 2);
    uint64_t value;

    if (sizeof(lua_Integer) < 8)
        value = (uint64_t)luaL_checknumber(L, 3);
    else
        value = (uint64_t)luaL_checkinteger(L, 3);

    return __eco_nlmsg_put_attr(L, msg, type, sizeof(uint64_t), &value);
}

static int eco_nlmsg_put_attr_str(lua_State *L)
{
    struct eco_nlmsg *msg = luaL_checkudata(L, 1, NLMSG_USER_MT);
    int type = luaL_checkinteger(L, 2);
    const char *value = lua_tostring(L, 3);

    return __eco_nlmsg_put_attr(L, msg, type, strlen(value), value);
}

static int eco_nlmsg_put_attr_strz(lua_State *L)
{
    struct eco_nlmsg *msg = luaL_checkudata(L, 1, NLMSG_USER_MT);
    int type = luaL_checkinteger(L, 2);
    const char *value = lua_tostring(L, 3);

    return __eco_nlmsg_put_attr(L, msg, type, strlen(value) + 1, value);
}

static int eco_nlmsg_put_attr_nest_start(lua_State *L)
{
    struct eco_nlmsg *msg = luaL_checkudata(L, 1, NLMSG_USER_MT);
    int type = luaL_checkinteger(L, 2);

    return __eco_nlmsg_put_attr(L, msg, type | NLA_F_NESTED, 0, NULL);
}

static int eco_nlmsg_put_attr_nest_end(lua_State *L)
{
    struct eco_nlmsg *msg = luaL_checkudata(L, 1, NLMSG_USER_MT);

    msg->nest = NULL;
    lua_settop(L, 1);

    return 1;
}

static const struct luaL_Reg nlmsg_user_methods[] = {
    {"binary", eco_nlmsg_to_binary},
    {"put", eco_nlmsg_put},
    {"put_attr", eco_nlmsg_put_attr},
    {"put_attr_flag", eco_nlmsg_put_attr_flag},
    {"put_attr_u8", eco_nlmsg_put_attr_u8},
    {"put_attr_u16", eco_nlmsg_put_attr_u16},
    {"put_attr_u32", eco_nlmsg_put_attr_u32},
    {"put_attr_u64", eco_nlmsg_put_attr_u64},
    {"put_attr_str", eco_nlmsg_put_attr_str},
    {"put_attr_strz", eco_nlmsg_put_attr_strz},
    {"put_attr_nest_start", eco_nlmsg_put_attr_nest_start},
    {"put_attr_nest_end", eco_nlmsg_put_attr_nest_end},
    {NULL, NULL}
};

static int lua_new_nlmsg_user(lua_State *L)
{
    int type = luaL_checkinteger(L, 1);
    int flags = luaL_checkinteger(L, 2);
    int seq = luaL_optinteger(L, 3, 0);
    int size = luaL_optinteger(L, 4, 4096);
    struct eco_nlmsg *msg;
    struct nlmsghdr *nlh;

    size = NLMSG_SPACE(size);

    msg = lua_newuserdata(L, sizeof(struct eco_nlmsg) + size);
    luaL_setmetatable(L, NLMSG_USER_MT);

    memset(msg->buf, 0, NLMSG_ALIGN(sizeof(struct nlmsghdr)));

    nlh = (struct nlmsghdr *)msg->buf;
    nlh->nlmsg_len = NLMSG_ALIGN(sizeof(struct nlmsghdr));

    nlh->nlmsg_type = type;
    nlh->nlmsg_flags = flags;
    nlh->nlmsg_seq = seq;

    msg->nlh = nlh;
    msg->size = size;
    msg->nest = NULL;

    return 1;
}

static int lua_nl_attr_get_u8(lua_State *L)
{
    const struct nlattr *attr = (const struct nlattr *)luaL_checkstring(L, 1);
    int value = *((uint8_t *)nla_data(attr));
    lua_pushinteger(L, value);
    return 1;
}

static int lua_nl_attr_get_s8(lua_State *L)
{
    const struct nlattr *attr = (const struct nlattr *)luaL_checkstring(L, 1);
    int8_t value = *((int8_t *)nla_data(attr));
    lua_pushinteger(L, value);
    return 1;
}

static int lua_nl_attr_get_u16(lua_State *L)
{
    const struct nlattr *attr = (const struct nlattr *)luaL_checkstring(L, 1);
    int value = *((uint16_t *)nla_data(attr));
    lua_pushinteger(L, value);
    return 1;
}

static int lua_nl_attr_get_s16(lua_State *L)
{
    const struct nlattr *attr = (const struct nlattr *)luaL_checkstring(L, 1);
    int16_t value = *((int16_t *)nla_data(attr));
    lua_pushinteger(L, value);
    return 1;
}

static int lua_nl_attr_get_u32(lua_State *L)
{
    const struct nlattr *attr = (const struct nlattr *)luaL_checkstring(L, 1);
    uint32_t value = *((uint32_t *)nla_data(attr));
    lua_pushinteger(L, value);
    return 1;
}

static int lua_nl_attr_get_s32(lua_State *L)
{
    const struct nlattr *attr = (const struct nlattr *)luaL_checkstring(L, 1);
    int32_t value = *((int32_t *)nla_data(attr));
    lua_pushinteger(L, value);
    return 1;
}

static int lua_nl_attr_get_u64(lua_State *L)
{
    const struct nlattr *attr = (const struct nlattr *)luaL_checkstring(L, 1);
    uint64_t value = *((uint64_t *)nla_data(attr));

    /* overflow */
    if (value > INT64_MAX)
        value = INT64_MAX;

    lua_pushinteger(L, value);
    return 1;
}

static int lua_nl_attr_get_s64(lua_State *L)
{
    const struct nlattr *attr = (const struct nlattr *)luaL_checkstring(L, 1);
    int64_t value = *((int64_t *)nla_data(attr));

    lua_pushinteger(L, value);
    return 1;
}

static int lua_nl_attr_get_str(lua_State *L)
{
    const struct nlattr *attr = (const struct nlattr *)luaL_checkstring(L, 1);
    const char *value = nla_data(attr);
    lua_pushstring(L, value);
    return 1;
}

static int lua_nl_attr_get_payload(lua_State *L)
{
    const struct nlattr *attr = (const struct nlattr *)luaL_checkstring(L, 1);
    lua_pushlstring(L, nla_data(attr), nla_len(attr));
    return 1;
}

static int lua_nl_parse_attr_nested(lua_State *L)
{
    const struct nlattr *nest = (const struct nlattr *)luaL_checkstring(L, 1);
    const struct nlattr *attr;
    int rem;

    lua_newtable(L);

    nla_for_each_nested(attr, nest, rem) {
        lua_pushlstring(L, (const char *)attr, attr->nla_len);
        lua_rawseti(L, -2, nla_type(attr));
    }

    return 1;
}

static const luaL_Reg funcs[] = {
    {"attr_get_u8", lua_nl_attr_get_u8},
    {"attr_get_s8", lua_nl_attr_get_s8},
    {"attr_get_u16", lua_nl_attr_get_u16},
    {"attr_get_s16", lua_nl_attr_get_s16},
    {"attr_get_u32", lua_nl_attr_get_u32},
    {"attr_get_s32", lua_nl_attr_get_s32},
    {"attr_get_u64", lua_nl_attr_get_u64},
    {"attr_get_s64", lua_nl_attr_get_s64},
    {"attr_get_str", lua_nl_attr_get_str},
    {"attr_get_payload", lua_nl_attr_get_payload},
    {"parse_attr_nested", lua_nl_parse_attr_nested},
    {NULL, NULL}
};

int luaopen_eco_internal_nl(lua_State *L)
{
    creat_metatable(L, NLMSG_USER_MT, NULL, nlmsg_user_methods);
    creat_metatable(L, NLMSG_KER_MT, NULL, nlmsg_ker_methods);

    luaL_newlib(L, funcs);

    lua_add_constant(L, "NLMSG_NOOP", NLMSG_NOOP);
    lua_add_constant(L, "NLMSG_ERROR", NLMSG_ERROR);
    lua_add_constant(L, "NLMSG_DONE", NLMSG_DONE);
    lua_add_constant(L, "NLMSG_OVERRUN", NLMSG_OVERRUN);

    lua_add_constant(L, "NLMSG_MIN_TYPE", NLMSG_MIN_TYPE);

    lua_add_constant(L, "NLM_F_REQUEST", NLM_F_REQUEST);
    lua_add_constant(L, "NLM_F_MULTI", NLM_F_MULTI);
    lua_add_constant(L, "NLM_F_ACK", NLM_F_ACK);
    lua_add_constant(L, "NLM_F_ECHO", NLM_F_ECHO);
    lua_add_constant(L, "NLM_F_DUMP_INTR", NLM_F_DUMP_INTR);
    lua_add_constant(L, "NLM_F_DUMP_FILTERED", NLM_F_DUMP_FILTERED);
    lua_add_constant(L, "NLM_F_ROOT", NLM_F_ROOT);
    lua_add_constant(L, "NLM_F_MATCH", NLM_F_MATCH);
    lua_add_constant(L, "NLM_F_ATOMIC", NLM_F_ATOMIC);
    lua_add_constant(L, "NLM_F_DUMP", NLM_F_DUMP);
    lua_add_constant(L, "NLM_F_REPLACE", NLM_F_REPLACE);
    lua_add_constant(L, "NLM_F_EXCL", NLM_F_EXCL);
    lua_add_constant(L, "NLM_F_CREATE", NLM_F_CREATE);
    lua_add_constant(L, "NLM_F_APPEND", NLM_F_APPEND);
    lua_add_constant(L, "NLM_F_NONREC", NLM_F_NONREC);
    lua_add_constant(L, "NLM_F_CAPPED", NLM_F_CAPPED);
    lua_add_constant(L, "NLM_F_ACK_TLVS", NLM_F_ACK_TLVS);

    lua_add_constant(L, "NLMSGERR_ATTR_MSG", NLMSGERR_ATTR_MSG);
    lua_add_constant(L, "NLMSGERR_ATTR_OFFS", NLMSGERR_ATTR_OFFS);
    lua_add_constant(L, "NLMSGERR_ATTR_COOKIE", NLMSGERR_ATTR_COOKIE);

    lua_add_constant(L, "NLMSGERR_SIZE", sizeof(struct nlmsgerr));

    lua_add_constant(L, "NETLINK_ROUTE", NETLINK_ROUTE);
    lua_add_constant(L, "NETLINK_UNUSED", NETLINK_UNUSED);
    lua_add_constant(L, "NETLINK_USERSOCK", NETLINK_USERSOCK);
    lua_add_constant(L, "NETLINK_FIREWALL", NETLINK_FIREWALL);
    lua_add_constant(L, "NETLINK_SOCK_DIAG", NETLINK_SOCK_DIAG);
    lua_add_constant(L, "NETLINK_NFLOG", NETLINK_NFLOG);
    lua_add_constant(L, "NETLINK_XFRM", NETLINK_XFRM);
    lua_add_constant(L, "NETLINK_SELINUX", NETLINK_SELINUX);
    lua_add_constant(L, "NETLINK_ISCSI", NETLINK_ISCSI);
    lua_add_constant(L, "NETLINK_AUDIT", NETLINK_AUDIT);
    lua_add_constant(L, "NETLINK_FIB_LOOKUP", NETLINK_FIB_LOOKUP);
    lua_add_constant(L, "NETLINK_CONNECTOR", NETLINK_CONNECTOR);
    lua_add_constant(L, "NETLINK_NETFILTER", NETLINK_NETFILTER);
    lua_add_constant(L, "NETLINK_IP6_FW", NETLINK_IP6_FW);
    lua_add_constant(L, "NETLINK_DNRTMSG", NETLINK_DNRTMSG);
    lua_add_constant(L, "NETLINK_KOBJECT_UEVENT", NETLINK_KOBJECT_UEVENT);
    lua_add_constant(L, "NETLINK_GENERIC", NETLINK_GENERIC);

    lua_pushcfunction(L, lua_new_nlmsg_user);
    lua_setfield(L, -2, "nlmsg");
    
    lua_pushcfunction(L, lua_new_nlmsg_ker);
    lua_setfield(L, -2, "nlmsg_ker");

    return 1;
}
