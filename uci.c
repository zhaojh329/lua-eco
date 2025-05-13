/* SPDX-License-Identifier: MIT */
/*
 * Author: Jianhui Zhao <zhaojh329@gmail.com>
 *
 * Modified from https://github.com/openwrt/uci/blob/master/lua/uci.c
 */

#include <stdlib.h>
#include <uci.h>

#include "eco.h"

#define UCI_MT "eco{uci}"

static int lua_uci_close(lua_State *L)
{
    struct uci_context **ctx = luaL_checkudata(L, 1, UCI_MT);

    if (!*ctx)
        return 0;

    uci_free_context(*ctx);

    *ctx = NULL;

    return 0;
}

static struct uci_package *find_package(lua_State *L,
        struct uci_context *ctx, const char *str, bool all)
{
    struct uci_package *p = NULL;
    struct uci_element *e;
    char *sep;
    char *name;

    sep = strchr(str, '.');
    if (sep) {
        name = malloc(1 + sep - str);
        if (!name) {
            luaL_error(L, "out of memory");
            return NULL;
        }

        strncpy(name, str, sep - str);
        name[sep - str] = 0;
    } else {
        name = (char *)str;
    }

    uci_foreach_element(&ctx->root, e) {
        if (strcmp(e->name, name) != 0)
            continue;

        p = uci_to_package(e);
        goto done;
    }

    if (all)
        uci_load(ctx, name, &p);

done:
    if (name != str)
       free(name);
    return p;
}

static int lookup_extended(struct uci_context *ctx, struct uci_ptr *ptr, char *str, bool extended)
{	
    struct uci_ptr lookup;
    int rv;

    /* use a copy of the passed ptr since failing lookups will
    * clobber the state */
    lookup = *ptr;
    lookup.flags |= UCI_LOOKUP_EXTENDED;

    rv = uci_lookup_ptr(ctx, &lookup, str, extended);

    /* copy to passed ptr on success */
    if (!rv)
        *ptr = lookup;

    return rv;
}

static int lookup_ptr(struct uci_context *ctx, struct uci_ptr *ptr, char *str, bool extended)
{
    if (ptr && !ptr->s && ptr->section && *ptr->section == '@')
        return lookup_extended(ctx, ptr, str, extended);

    return uci_lookup_ptr(ctx, ptr, str, extended);
}

static int lookup_args(lua_State *L, struct uci_context *ctx, struct uci_ptr *ptr, char **buf)
{
    char *s = NULL;
    int n;

    n = lua_gettop(L);
    luaL_checkstring(L, 2);
    s = strdup(lua_tostring(L, 2));
    if (!s)
        goto error;

    memset(ptr, 0, sizeof(struct uci_ptr));

    if (!find_package(L, ctx, s, true))
        goto error;

    switch (n - 1) {
    case 4:
    case 3:
        ptr->option = luaL_checkstring(L, 4);
        /* fall through */
    case 2:
        ptr->section = luaL_checkstring(L, 3);
        ptr->package = luaL_checkstring(L, 2);
        if (lookup_ptr(ctx, ptr, NULL, true) != UCI_OK)
            goto error;
        break;
    case 1:
        if (lookup_ptr(ctx, ptr, s, true) != UCI_OK)
            goto error;
        break;
    default:
        luaL_error(L, "invalid argument count");
        goto error;
    }

    *buf = s;
    return 0;

error:
    if (s)
        free(s);
    return 1;
}

static int uci_push_status(lua_State *L, struct uci_context *ctx, bool hasarg)
{
    char *str = NULL;

    if (!hasarg)
        lua_pushboolean(L, (ctx->err == UCI_OK));

    if (ctx->err) {
        uci_get_errorstr(ctx, &str, "uci");

        if (str) {
            lua_pushstring(L, str);
            free(str);
            return 2;
        }
    }

    return 1;
}

static void uci_push_option(lua_State *L, struct uci_option *o)
{
    struct uci_element *e;
    int i = 0;

    switch(o->type) {
    case UCI_TYPE_STRING:
        lua_pushstring(L, o->v.string);
        break;
    case UCI_TYPE_LIST:
        lua_newtable(L);
        uci_foreach_element(&o->v.list, e) {
            i++;
            lua_pushstring(L, e->name);
            lua_rawseti(L, -2, i);
        }
        break;
    default:
        lua_pushnil(L);
        break;
    }
}

static void uci_push_section(lua_State *L, struct uci_section *s, int index)
{
    struct uci_element *e;

    lua_newtable(L);
    lua_pushboolean(L, s->anonymous);
    lua_setfield(L, -2, ".anonymous");
    lua_pushstring(L, s->type);
    lua_setfield(L, -2, ".type");
    lua_pushstring(L, s->e.name);
    lua_setfield(L, -2, ".name");
    if (index >= 0) {
        lua_pushinteger(L, index);
        lua_setfield(L, -2, ".index");
    }

    uci_foreach_element(&s->options, e) {
        struct uci_option *o = uci_to_option(e);
        uci_push_option(L, o);
        lua_setfield(L, -2, o->e.name);
    }
}

static void uci_push_package(lua_State *L, struct uci_package *p)
{
    struct uci_element *e;
    int i = 0;

    lua_newtable(L);

    uci_foreach_element(&p->sections, e) {
        uci_push_section(L, uci_to_section(e), i);
        lua_setfield(L, -2, e->name);
        i++;
    }
}

static struct uci_context *lua_uci_check_ctx(lua_State *L)
{
    struct uci_context *ctx = *(struct uci_context **)luaL_checkudata(L, 1, UCI_MT);
    if (!ctx) {
        luaL_error(L, "UCI context closed");
        return NULL;
    }

    return ctx;
}

static int lua_uci_unload(lua_State *L)
{
    struct uci_context *ctx = lua_uci_check_ctx(L);    
    const char *s = luaL_checkstring(L, 2);
    struct uci_package *p;

    p = find_package(L, ctx, s, false);
    if (p) {
        uci_unload(ctx, p);
        return uci_push_status(L, ctx, false);
    } else {
        lua_pushboolean(L, 0);
    }

    return 1;
}

static int lua_uci_load(lua_State *L)
{
    struct uci_context *ctx = lua_uci_check_ctx(L);
    struct uci_package *p = NULL;
    const char *s;

    lua_uci_unload(L);
    lua_pop(L, 1); /* bool ret value of unload */
    s = lua_tostring(L, -1);

    uci_load(ctx, s, &p);
    return uci_push_status(L, ctx, false);
}

static int __lua_uci_get(lua_State *L, bool all)
{
    struct uci_context *ctx = lua_uci_check_ctx(L);
    struct uci_ptr ptr;
	char *s = NULL;
	int nret = 1;
    
    if (lookup_args(L, ctx, &ptr, &s))
        goto error;

    if (!all && !ptr.s) {
        ctx->err = UCI_ERR_INVAL;
        goto error;
    }

    if (!(ptr.flags & UCI_LOOKUP_COMPLETE)) {
        ctx->err = UCI_ERR_NOTFOUND;
        goto error;
    }

    if (ptr.o) {
        uci_push_option(L, ptr.o);
    } else if (ptr.s) {
        if (all) {
            uci_push_section(L, ptr.s, -1);
        }
        else {
            lua_pushstring(L, ptr.s->type);
            lua_pushstring(L, ptr.s->e.name);
            nret++;
        }
    } else {
        uci_push_package(L, ptr.p);
    }

    if (s)
        free(s);
    return nret;

error:
    if (s)
        free(s);

    lua_pushnil(L);
    return uci_push_status(L, ctx, true);
}

static int lua_uci_get(lua_State *L)
{
    return __lua_uci_get(L, false);
}

static int lua_uci_get_all(lua_State *L)
{
    return __lua_uci_get(L, true);
}

static int lua_uci_add(lua_State *L)
{
    struct uci_context *ctx = lua_uci_check_ctx(L);
    const char *package = luaL_checkstring(L, 2);
    const char *type = luaL_checkstring(L, 3);
    struct uci_package *p;
    struct uci_section *s = NULL;
    const char *name = NULL;

    p = find_package(L, ctx, package, true);
    if (!p)
        goto fail;

    if (uci_add_section(ctx, p, type, &s) || !s)
        goto fail;

    name = s->e.name;
    lua_pushstring(L, name);
    return 1;

fail:
    lua_pushnil(L);
    return uci_push_status(L, ctx, true);
}

static int lua_uci_set(lua_State *L)
{
    struct uci_context *ctx = lua_uci_check_ctx(L);
    int nargs = lua_gettop(L);
    struct uci_ptr ptr;
    bool istable = false;
    int err = UCI_ERR_MEM;
    char *s = NULL;
    const char *v;
    unsigned int i;

    if (lookup_args(L, ctx, &ptr, &s))
        goto error;

    switch(nargs - 1) {
    case 1:
        /* Format: uci.set("p.s.o=v") or uci.set("p.s=v") */
        break;
    case 4:
        /* Format: uci.set("p", "s", "o", "v") */
        if (lua_istable(L, nargs)) {
            if (lua_rawlen(L, nargs) < 1) {
                free(s);
                return luaL_error(L, "Cannot set an uci option to an empty table value");
            }
            lua_rawgeti(L, nargs, 1);
            ptr.value = luaL_checkstring(L, -1);
            lua_pop(L, 1);
            istable = true;
        } else {
            ptr.value = luaL_checkstring(L, nargs);
        }
        break;
    case 3:
        /* Format: uci.set("p", "s", "v") */
        ptr.value = ptr.option;
        ptr.option = NULL;
        break;
    default:
        ctx->err = UCI_ERR_INVAL;
        goto error;
    }

    err = lookup_ptr(ctx, &ptr, NULL, true);
    if (err)
        goto error;

    if ((!ptr.s && ptr.option) || !ptr.value) {
        ctx->err = UCI_ERR_INVAL;
        goto error;
    }

    if (istable) {
        if (lua_rawlen(L, nargs) == 1) {
            i = 1;
            if (ptr.o) {
                v = ptr.value;
                ptr.value = NULL;
                err = uci_delete(ctx, &ptr);
                if (err)
                    goto error;
                ptr.value = v;
            }
    } else {
        i = 2;
        err = uci_set(ctx, &ptr);
        if (err)
            goto error;
    }

    for (; i <= lua_rawlen(L, nargs); i++) {
        lua_rawgeti(L, nargs, i);
        ptr.value = luaL_checkstring(L, -1);
        err = uci_add_list(ctx, &ptr);
        lua_pop(L, 1);
        if (err)
            goto error;
    }
    } else {
        err = uci_set(ctx, &ptr);
        if (err)
            goto error;
    }

error:
    if (s)
        free(s);
    return uci_push_status(L, ctx, false);
}

static int lua_uci_rename(lua_State *L)
{
    struct uci_context *ctx = lua_uci_check_ctx(L);
    int nargs = lua_gettop(L);
    int err = UCI_ERR_MEM;
    struct uci_ptr ptr;
    char *s = NULL;

    if (lookup_args(L, ctx, &ptr, &s))
        goto error;

    switch(nargs - 1) {
    case 1:
        /* Format: uci.set("p.s.o=v") or uci.set("p.s=v") */
        break;
    case 4:
        /* Format: uci.set("p", "s", "o", "v") */
        ptr.value = luaL_checkstring(L, nargs);
        break;
    case 3:
        /* Format: uci.set("p", "s", "v") */
        ptr.value = ptr.option;
        ptr.option = NULL;
        break;
    default:
        ctx->err = UCI_ERR_INVAL;
        goto error;
    }

    err = lookup_ptr(ctx, &ptr, NULL, true);
    if (err)
        goto error;

    if (((ptr.s == NULL) && (ptr.option != NULL)) || (ptr.value == NULL)) {
        ctx->err = UCI_ERR_INVAL;
        goto error;
    }

    err = uci_rename(ctx, &ptr);
    if (err)
        goto error;

error:
    if (s)
        free(s);
    return uci_push_status(L, ctx, false);
}

enum {
    CMD_SAVE,
    CMD_COMMIT,
    CMD_REVERT
};

static int uci_lua_package_cmd(lua_State *L, int cmd)
{
    struct uci_context *ctx = lua_uci_check_ctx(L);
    int nargs = lua_gettop(L);
    struct uci_element *e, *tmp;
    struct uci_ptr ptr;
    char *s = NULL;
    
    if ((cmd != CMD_REVERT) && (nargs - 1 > 1))
        goto err;

    if (lookup_args(L, ctx, &ptr, &s))
        goto err;

    lookup_ptr(ctx, &ptr, NULL, true);

    uci_foreach_element_safe(&ctx->root, tmp, e) {
        struct uci_package *p = uci_to_package(e);

        if (ptr.p && (ptr.p != p))
            continue;

        ptr.p = p;
        switch(cmd) {
        case CMD_COMMIT:
            uci_commit(ctx, &p, false);
            break;
        case CMD_SAVE:
            uci_save(ctx, p);
            break;
        case CMD_REVERT:
            uci_revert(ctx, &ptr);
            break;
        }
    }

err:
    if (s)
        free(s);
    return uci_push_status(L, ctx, false);
}

static int lua_uci_save(lua_State *L)
{
    return uci_lua_package_cmd(L, CMD_SAVE);
}

static int lua_uci_delete(lua_State *L)
{
    struct uci_context *ctx = lua_uci_check_ctx(L);
    struct uci_ptr ptr;
    char *s = NULL;

    if (lookup_args(L, ctx, &ptr, &s))
        goto error;

    uci_delete(ctx, &ptr);

error:
    if (s)
        free(s);
    return uci_push_status(L, ctx, false);
}

static int lua_uci_commit(lua_State *L)
{
    return uci_lua_package_cmd(L, CMD_COMMIT);
}

static int lua_uci_revert(lua_State *L)
{
    return uci_lua_package_cmd(L, CMD_REVERT);
}

static int lua_uci_reorder(lua_State *L)
{
    struct uci_context *ctx = lua_uci_check_ctx(L);
    int nargs = lua_gettop(L);
    int err = UCI_ERR_MEM;
    struct uci_ptr ptr;
    char *s = NULL;

    if (lookup_args(L, ctx, &ptr, &s))
        goto error;

    switch(nargs - 1) {
    case 1:
        /* Format: uci.set("p.s=v") or uci.set("p.s=v") */
        if (ptr.option) {
            ctx->err = UCI_ERR_INVAL;
            goto error;
        }
        break;
    case 3:
        /* Format: uci.set("p", "s", "v") */
        ptr.value = ptr.option;
        ptr.option = NULL;
        break;
    default:
        ctx->err = UCI_ERR_INVAL;
        goto error;
    }

    err = lookup_ptr(ctx, &ptr, NULL, true);
    if (err)
        goto error;

    if ((ptr.s == NULL) || (ptr.value == NULL)) {
        ctx->err = UCI_ERR_INVAL;
        goto error;
    }

    err = uci_reorder_section(ctx, ptr.s, strtoul(ptr.value, NULL, 10));
    if (err)
        goto error;

error:
    if (s)
        free(s);
    return uci_push_status(L, ctx, false);
}

static int lua_uci_foreach(lua_State *L)
{
    struct uci_context *ctx = lua_uci_check_ctx(L);
    const char *package = luaL_checkstring(L, 2);
    struct uci_element *e, *tmp;
    struct uci_package *p;
    const char *type;
    bool ret = false;
    int i = 0;

    if (lua_isnil(L, 3))
        type = NULL;
    else
        type = luaL_checkstring(L, 3);

    if (!lua_isfunction(L, 4) || !package)
        return luaL_error(L, "Invalid argument");

    p = find_package(L, ctx, package, true);
    if (!p)
        goto done;

    uci_foreach_element_safe(&p->sections, tmp, e) {
        struct uci_section *s = uci_to_section(e);

        i++;

        if (type && (strcmp(s->type, type) != 0))
            continue;

        lua_pushvalue(L, 4); /* iterator function */
        uci_push_section(L, s, i - 1);
        if (lua_pcall(L, 1, 1, 0) == 0) {
            ret = true;
            if (lua_isboolean(L, -1) && !lua_toboolean(L, -1))
                break;
        } else {
            lua_error(L);
            break;
        }
    }

done:
    lua_pushboolean(L, ret);
    return 1;
}

static int lua_uci_each_iter(lua_State *L)
{
    const char *type = lua_tostring(L, lua_upvalueindex(1));
    const struct uci_list *list = lua_topointer(L, lua_upvalueindex(2));
    struct uci_element *e = (struct uci_element *)lua_topointer(L, lua_upvalueindex(3));
    struct uci_element *tmp = (struct uci_element *)lua_topointer(L, lua_upvalueindex(4));
    int i = lua_tointeger(L, lua_upvalueindex(5));
    struct uci_section *s;

again:
    if (i) {
        e = tmp;
        tmp = list_to_element(e->list.next);
    }

    if (&e->list == list)
        return 0;

    s = uci_to_section(e);

    i++;

    if (type && (strcmp(s->type, type) != 0))
        goto again;

    lua_pushlightuserdata(L, e);
    lua_replace(L, lua_upvalueindex(3));

    lua_pushlightuserdata(L, tmp);
    lua_replace(L, lua_upvalueindex(4));

    lua_pushinteger(L, i);
    lua_replace(L, lua_upvalueindex(5));

    uci_push_section(L, s, i - 1);

    return 1;
}

static int lua_uci_each(lua_State *L)
{
    struct uci_context *ctx = lua_uci_check_ctx(L);
    const char *package = luaL_checkstring(L, 2);
    const char *type = lua_tostring(L, 3);
    struct uci_element *e, *tmp;
    struct uci_package *p;
    int i = 0;

    p = find_package(L, ctx, package, true);
    if (!p) {
        lua_pushnil(L);
        return 1;
    }

    e = list_to_element(p->sections.next);
    tmp = list_to_element(e->list.next);

    if (type)
        lua_pushstring(L, type);
    else
        lua_pushnil(L);

    lua_pushlightuserdata(L, &p->sections);
    lua_pushlightuserdata(L, e);
    lua_pushlightuserdata(L, tmp);
    lua_pushinteger(L, i);

    lua_pushcclosure(L, lua_uci_each_iter, 5);
    return 1;
}

static int lua_uci_get_confdir(lua_State *L)
{
    struct uci_context *ctx = lua_uci_check_ctx(L);
    lua_pushstring(L, ctx->confdir);
    return 1;
}

static int lua_uci_set_confdir(lua_State *L)
{
    struct uci_context *ctx = lua_uci_check_ctx(L);

    luaL_checkstring(L, 2);
    uci_set_confdir(ctx, lua_tostring(L, -1));
    return uci_push_status(L, ctx, false);
}

static int lua_uci_get_savedir(lua_State *L)
{
    struct uci_context *ctx = lua_uci_check_ctx(L);
    lua_pushstring(L, ctx->savedir);
    return 1;
}

static int lua_uci_set_savedir(lua_State *L)
{
    struct uci_context *ctx = lua_uci_check_ctx(L);
    const char *dir = luaL_checkstring(L, 2);

    uci_set_savedir(ctx, dir);
    return uci_push_status(L, ctx, false);
}

static int lua_uci_list_configs(lua_State *L)
{
    struct uci_context *ctx = lua_uci_check_ctx(L);
    char **configs = NULL;
    char **ptr;
    int i = 1;

    if ((uci_list_configs(ctx, &configs) != UCI_OK) || !configs)
        return uci_push_status(L, ctx, false);

    lua_newtable(L);

    for (ptr = configs; *ptr; ptr++) {
        lua_pushstring(L, *ptr);
        lua_rawseti(L, -2, i++);
    }

    free(configs);
    return 1;
}

static const luaL_Reg uci_methods[] = {
    {"close", lua_uci_close},
    {"load", lua_uci_load},
    {"unload", lua_uci_unload},
    {"get", lua_uci_get},
    {"get_all", lua_uci_get_all},
    {"add", lua_uci_add},
    {"set", lua_uci_set},
    {"rename", lua_uci_rename},
    {"save", lua_uci_save},
    {"delete", lua_uci_delete},
    {"commit", lua_uci_commit},
    {"revert", lua_uci_revert},
    {"reorder", lua_uci_reorder},
    {"foreach", lua_uci_foreach},
    {"each", lua_uci_each},
    {"get_confdir", lua_uci_get_confdir},
    {"set_confdir", lua_uci_set_confdir},
    {"get_savedir", lua_uci_get_savedir},
    {"set_savedir", lua_uci_set_savedir},
    {"list_configs", lua_uci_list_configs},
    {NULL, NULL}
};

static const luaL_Reg uci_mt[] = {
    {"__gc", lua_uci_close},
    {"__close", lua_uci_close},
    {NULL, NULL}
};

static int lua_uci_cursor(lua_State *L)
{
    struct uci_context **ctx = lua_newuserdata(L, sizeof(struct uci_context *));
    int nargs = lua_gettop(L) - 1;
    const char *dir;

    *ctx = uci_alloc_context();
    if (!*ctx)
        return luaL_error(L, "Cannot allocate UCI context");

    switch (nargs) {
    case 0:
        break;
    case 2:
        dir = luaL_checkstring(L, 2);
        if (uci_set_savedir(*ctx, dir) != UCI_OK)
            return luaL_error(L, "Unable to set savedir");
        /* fall through */
    case 1:
        dir = luaL_checkstring(L, 1);
        if (uci_set_confdir(*ctx, dir) != UCI_OK)
            return luaL_error(L, "Unable to set confdir");
        break;
    default:
        return luaL_error(L, "Invalid args");
    }

    lua_pushvalue(L, lua_upvalueindex(1));
    lua_setmetatable(L, -2);

    return 1;
}

int luaopen_eco_uci(lua_State *L)
{
    lua_newtable(L);

    eco_new_metatable(L, UCI_MT, uci_mt, uci_methods);
    lua_pushcclosure(L, lua_uci_cursor, 1);
    lua_setfield(L, -2, "cursor");

    return 1;
}
