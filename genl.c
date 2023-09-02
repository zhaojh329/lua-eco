/* SPDX-License-Identifier: MIT */
/*
 * Author: Jianhui Zhao <zhaojh329@gmail.com>
 */

#include <linux/genetlink.h>

#include "nl.h"

static int eco_genl_new_genlmsghdr(lua_State *L)
{
    struct genlmsghdr genl = {};

    luaL_checktype(L, 1, LUA_TTABLE);

    lua_getfield(L, 1, "cmd");
    genl.cmd = lua_tointeger(L, -1);

    lua_getfield(L, 1, "version");
    genl.version = luaL_optinteger(L, -1, 1);

    lua_pushlstring(L, (const char *)&genl, sizeof(genl));
    return 1;
}

static int eco_genl_parse_genlmsghdr(lua_State *L)
{
    struct eco_nlmsg *msg = luaL_checkudata(L, 1, ECO_NLMSG_KER_MT);
    struct nlmsghdr *nlh = msg->nlh;
    struct genlmsghdr *genl;

    if (!NLMSG_OK(nlh, msg->size)) {
        lua_pushnil(L);
        lua_pushliteral(L, "invalid nlmsg");
        return 2;
    }

    if (nlh->nlmsg_type < NLMSG_MIN_TYPE) {
        lua_pushnil(L);
        lua_pushliteral(L, "invalid nlmsg type");
        return 2;
    }

	genl = NLMSG_DATA(nlh);

    lua_newtable(L);

    lua_pushinteger(L, genl->cmd);
    lua_setfield(L, -2, "cmd");

    lua_pushinteger(L, genl->version);
    lua_setfield(L, -2, "version");

    return 1;
}

static const luaL_Reg funcs[] = {
    {"genlmsghdr", eco_genl_new_genlmsghdr},
    {"parse_genlmsghdr", eco_genl_parse_genlmsghdr},
    {NULL, NULL}
};

int luaopen_eco_core_genl(lua_State *L)
{
    luaL_newlib(L, funcs);

    lua_add_constant(L, "GENL_ID_CTRL", GENL_ID_CTRL);

    lua_add_constant(L, "CTRL_CMD_UNSPEC", CTRL_CMD_UNSPEC);
    lua_add_constant(L, "CTRL_CMD_NEWFAMILY", CTRL_CMD_NEWFAMILY);
    lua_add_constant(L, "CTRL_CMD_DELFAMILY", CTRL_CMD_DELFAMILY);
    lua_add_constant(L, "CTRL_CMD_GETFAMILY", CTRL_CMD_GETFAMILY);
    lua_add_constant(L, "CTRL_CMD_NEWOPS", CTRL_CMD_NEWOPS);
    lua_add_constant(L, "CTRL_CMD_DELOPS", CTRL_CMD_DELOPS);
    lua_add_constant(L, "CTRL_CMD_GETOPS", CTRL_CMD_GETOPS);
    lua_add_constant(L, "CTRL_CMD_NEWMCAST_GRP", CTRL_CMD_NEWMCAST_GRP);
    lua_add_constant(L, "CTRL_CMD_DELMCAST_GRP", CTRL_CMD_DELMCAST_GRP);
    lua_add_constant(L, "CTRL_CMD_GETMCAST_GRP", CTRL_CMD_GETMCAST_GRP);

    lua_add_constant(L, "CTRL_ATTR_UNSPEC", CTRL_ATTR_UNSPEC);
    lua_add_constant(L, "CTRL_ATTR_FAMILY_ID", CTRL_ATTR_FAMILY_ID);
    lua_add_constant(L, "CTRL_ATTR_FAMILY_NAME", CTRL_ATTR_FAMILY_NAME);
    lua_add_constant(L, "CTRL_ATTR_VERSION", CTRL_ATTR_VERSION);
    lua_add_constant(L, "CTRL_ATTR_HDRSIZE", CTRL_ATTR_HDRSIZE);
    lua_add_constant(L, "CTRL_ATTR_MAXATTR", CTRL_ATTR_MAXATTR);
    lua_add_constant(L, "CTRL_ATTR_OPS", CTRL_ATTR_OPS);
    lua_add_constant(L, "CTRL_ATTR_MCAST_GROUPS", CTRL_ATTR_MCAST_GROUPS);

    lua_add_constant(L, "CTRL_ATTR_OP_ID", CTRL_ATTR_OP_ID);
    lua_add_constant(L, "CTRL_ATTR_OP_FLAGS", CTRL_ATTR_OP_FLAGS);

    lua_add_constant(L, "CTRL_ATTR_MCAST_GRP_NAME", CTRL_ATTR_MCAST_GRP_NAME);
    lua_add_constant(L, "CTRL_ATTR_MCAST_GRP_ID", CTRL_ATTR_MCAST_GRP_ID);

    lua_add_constant(L, "GENLMSGHDR_SIZE", sizeof(struct genlmsghdr));

    return 1;
}
