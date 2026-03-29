/* SPDX-License-Identifier: MIT */
/*
 * Author: Jianhui Zhao <zhaojh329@gmail.com>
 */

#include <libubus.h>

#include "eco.h"

#define UBUS_MAX_MSGLEN 1048576

#define UBUS_CTX_MT "struct lua_ubus_context *"

enum {
    LUA_UBUS_OBJ_OBJECT,
    LUA_UBUS_OBJ_REQUEST,
    LUA_UBUS_OBJ_EVENT,
    LUA_UBUS_OBJ_SUBSCRIBER,
};

struct lua_ubus_context {
    struct ubus_context ctx;
    int connection_lost_cb;
    int data_cb;
    lua_State *co;
    char path[];
};

struct lua_ubus_object {
    struct ubus_object object;
    struct ubus_object_type type;
    struct blobmsg_policy *policy;
    struct ubus_method methods[0];
};

struct lua_ubus_subscriber {
    struct ubus_subscriber sub;
    char path[];
};

struct lua_ubus_event {
    struct ubus_event_handler ev;
    char pattern[];
};

static char ubus_obj_key;

static int push_ubus_error(lua_State *L, int ret)
{
    lua_pushnil(L);
    lua_pushstring(L, ubus_strerror(ret));
    return 2;
}

static void lua_table_to_blob_impl(lua_State *L, int index, struct blob_buf *b,
                   bool is_array, int visited)
{
    void *c;

    index = lua_absindex(L, index);
    visited = lua_absindex(L, visited);

    if (!lua_istable(L, index))
        return;

    lua_pushvalue(L, index);
    lua_rawget(L, visited);
    if (!lua_isnil(L, -1)) {
        lua_pop(L, 1);
        luaL_error(L, "circular reference in table");
        return;
    }
    lua_pop(L, 1);

    lua_pushvalue(L, index);
    lua_pushboolean(L, 1);
    lua_rawset(L, visited);

    for (lua_pushnil(L); lua_next(L, index); lua_pop(L, 2)) {
        const char *key;
        int type;

        lua_pushvalue(L, -2);
        lua_insert(L, -2);

        key = is_array ? NULL : lua_tostring(L, -2);

        type = lua_type(L, -1);

        switch (type) {
        case LUA_TBOOLEAN:
            blobmsg_add_u8(b, key, (uint8_t)lua_toboolean(L, -1));
            break;

        case LUA_TNUMBER: {
            if (lua_isinteger(L, -1)) {
                int64_t v = lua_tointeger(L, -1);
                if (v > INT32_MAX)
                    blobmsg_add_u64(b, key, v);
                else
                    blobmsg_add_u32(b, key, v);
            } else {
                blobmsg_add_double(b, key, lua_tonumber(L, -1));
            }
            break;
        }

        case LUA_TSTRING:
        case LUA_TUSERDATA:
        case LUA_TLIGHTUSERDATA:
            if (type == LUA_TSTRING) {
                blobmsg_add_string(b, key, lua_tostring(L, -1));
            } else {
                const char *val = lua_tostring(L, -1);
                if (val)
                    blobmsg_add_string(b, key, val);
            }
            break;

        case LUA_TTABLE:
            if (lua_table_is_array(L, -1)) {
                c = blobmsg_open_array(b, key);
                lua_table_to_blob_impl(L, lua_gettop(L), b, true, visited);
                blobmsg_close_array(b, c);
            } else {
                c = blobmsg_open_table(b, key);
                lua_table_to_blob_impl(L, lua_gettop(L), b, false, visited);
                blobmsg_close_table(b, c);
            }
            break;
        }
    }

    lua_pushvalue(L, index);
    lua_pushnil(L);
    lua_rawset(L, visited);
}

static void lua_table_to_blob(lua_State *L, int index, struct blob_buf *b, bool is_array)
{
    int visited;

    lua_newtable(L);
    visited = lua_gettop(L);

    lua_table_to_blob_impl(L, index, b, is_array, visited);

    lua_pop(L, 1);
}

static void blob_to_lua_table(lua_State *L, struct blob_attr *attr, size_t len, bool is_array);

static int __blob_to_lua_table(lua_State *L, struct blob_attr *attr, bool is_array)
{
    void *data;
    int off = 0;
    int len;

    if (!blobmsg_check_attr(attr, false))
        return 0;

    if (!is_array && blobmsg_name(attr)[0]) {
        lua_pushstring(L, blobmsg_name(attr));
        off++;
    }

    data = blobmsg_data(attr);
    len = blobmsg_data_len(attr);

    switch (blob_id(attr)) {
    case BLOBMSG_TYPE_BOOL:
        lua_pushboolean(L, *(uint8_t *)data);
        break;

    case BLOBMSG_TYPE_INT16:
        lua_pushinteger(L, (int16_t)be16_to_cpu(*(uint16_t *)data));
        break;

    case BLOBMSG_TYPE_INT32:
        lua_pushinteger(L, (int32_t)be32_to_cpu(*(uint32_t *)data));
        break;

    case BLOBMSG_TYPE_INT64:
        lua_pushinteger(L, (int64_t)be64_to_cpu(*(uint64_t *)data));
        break;

    case BLOBMSG_TYPE_DOUBLE: {
            union {
                double d;
                uint64_t u64;
            } v;
            v.u64 = be64_to_cpu(*(uint64_t *)data);
            lua_pushnumber(L, v.d);
        }
        break;

    case BLOBMSG_TYPE_STRING:
        lua_pushstring(L, data);
        break;

    case BLOBMSG_TYPE_ARRAY:
        blob_to_lua_table(L, data, len, true);
        break;

    case BLOBMSG_TYPE_TABLE:
        blob_to_lua_table(L, data, len, false);
        break;

    default:
        lua_pushnil(L);
        break;
    }

    return off + 1;
}

static void blob_to_lua_table(lua_State *L, struct blob_attr *attr, size_t len, bool is_array)
{
    struct blob_attr *pos;
    size_t rem = len;
    int idx = 1;
    int rv;

    lua_newtable(L);

    __blob_for_each_attr(pos, attr, rem) {
        rv = __blob_to_lua_table(L, pos, is_array);
        if (rv > 1)
            lua_rawset(L, -3);
        else if (rv > 0)
            lua_rawseti(L, -2, idx++);
    }
}

static int lua_arg_to_blob(lua_State *L, int idx, struct blob_buf *buf)
{
   if (!lua_isnoneornil(L, idx))
        luaL_checktype(L, idx, LUA_TTABLE);

    blob_buf_init(buf, 0);

    lua_table_to_blob(L, idx, buf, false);

    if (blob_pad_len(buf->head) > UBUS_MAX_MSGLEN) {
        blob_buf_free(buf);
        lua_pushnil(L);
        lua_pushliteral(L, "msg too long");
        return -1;
    }

    return 0;
}

static void lua_ubus_ctx_save_obj(lua_State *L, void *obj, int type)
{
    lua_getuservalue(L, 1);
    lua_pushinteger(L, type);
    lua_rawsetp(L, -2, obj);
    lua_pop(L, 1);
}

static void lua_ubus_get_ctx_uv(lua_State *L, int idx, void *ctx)
{
    if (idx) {
        lua_getuservalue(L, idx);
        return;
    }

    get_obj(L, &ubus_obj_key, ctx);
    lua_getuservalue(L, -1);
    lua_remove(L, -2);
}

static void lua_ubus_ctx_remove_obj(lua_State *L, int idx, void *ctx, void *obj)
{
    lua_ubus_get_ctx_uv(L, idx, ctx);
    lua_pushnil(L);
    lua_rawsetp(L, -2, obj);
    lua_pop(L, 1);
}

static bool lua_ubus_ctx_has_obj(lua_State *L, int idx, void *ctx, void *obj)
{
    bool exists;

    lua_ubus_get_ctx_uv(L, idx, ctx);
    lua_rawgetp(L, -1, obj);

    exists = !lua_isnil(L, -1);

    lua_pop(L, 2);

    return exists;
}

static const void *lua_checkludata(lua_State *L, int idx)
{
    luaL_checktype(L, idx, LUA_TLIGHTUSERDATA);
    return lua_topointer(L, idx);
}

static void lua_ubus_free_object(const struct lua_ubus_object *obj)
{
    int i, j;

    if (!obj)
        return;

    free((char *)obj->type.name);

    for (i = 0; i < obj->type.n_methods; i++) {
        const struct ubus_method *m = obj->methods + i;

        free((char *)m->name);

        for (j = 0; j < m->n_policy; j++)
            free((char *)m->policy[j].name);
    }

    free((void *)obj);
}

static int lua_ubus_strerror(lua_State *L)
{
    int ret = luaL_checkinteger(L, 1);

    lua_pushstring(L, ubus_strerror(ret));

    return 1;
}

static int lua_ubus_getfd(lua_State *L)
{
    struct lua_ubus_context *ctx = luaL_checkudata(L, 1, UBUS_CTX_MT);
    lua_pushinteger(L, ctx->ctx.sock.fd);
    return 1;
}

static int lua_ubus_handle_event(lua_State *L)
{
    struct lua_ubus_context *ctx = luaL_checkudata(L, 1, UBUS_CTX_MT);
    ctx->co = L;
    ubus_handle_event(&ctx->ctx);
    return 0;
}

static int lua_ubus_reregister_events(lua_State *L, struct lua_ubus_context *ctx)
{
    int ret = 0;

    lua_getuservalue(L, 1);
    lua_pushnil(L);

    while (lua_next(L, -2) != 0) {
        int type = lua_tointeger(L, -1);

        if (type == LUA_UBUS_OBJ_EVENT) {
            struct lua_ubus_event *lev = (struct lua_ubus_event *)lua_topointer(L, -2);

            ret = ubus_register_event_handler(&ctx->ctx, &lev->ev, lev->pattern);
            if (ret) {
                lua_pop(L, 2);
                break;
            }
        }

        lua_pop(L, 1);
    }

    lua_pop(L, 1);

    return ret;
}

static int lua_ubus_reconnect(lua_State *L)
{
    struct lua_ubus_context *ctx = luaL_checkudata(L, 1, UBUS_CTX_MT);
    const char *path = ctx->path[0] ? ctx->path : NULL;
    int ret;

    ret = ubus_reconnect(&ctx->ctx, path);
    if (ret) {
        lua_pushnil(L);
        return 1;
    }

    ret = lua_ubus_reregister_events(L, ctx);
    if (ret) {
        lua_pushnil(L);
        lua_pushstring(L, ubus_strerror(ret));
        return 2;
    }

    lua_pushinteger(L, ctx->ctx.sock.fd);

    return 1;
}

static int lua_ubus_abort_request(lua_State *L)
{
    struct lua_ubus_context *ctx = luaL_checkudata(L, 1, UBUS_CTX_MT);
    struct ubus_request *req = (struct ubus_request *)lua_checkludata(L, 2);

    ubus_abort_request(&ctx->ctx, req);
    free(req);
    return 0;
}

static int lua_ubus_complete_deferred_request(lua_State *L)
{
    struct lua_ubus_context *ctx = luaL_checkudata(L, 1, UBUS_CTX_MT);
    struct ubus_request_data *req = (struct ubus_request_data *)lua_checkludata(L, 2);
    int ret = luaL_checkinteger(L, 3);

    ubus_complete_deferred_request(&ctx->ctx, req, ret);
    free(req);
    return 0;
}

static void ubus_call_data_cb(struct ubus_request *req, int type, struct blob_attr *msg)
{
    struct lua_ubus_context *ctx = container_of(req->ctx, struct lua_ubus_context, ctx);
    lua_State *co = ctx->co;

    if (ctx->data_cb == LUA_NOREF)
        return;

    lua_rawgeti(co, LUA_REGISTRYINDEX, ctx->data_cb);

    get_obj(co, &ubus_obj_key, ctx);
    lua_pushlightuserdata(co, req);
    blob_to_lua_table(co, blob_data(msg), blob_len(msg), false);

    lua_call(co, 3, 0);
}

static void ubus_call_complete_cb(struct ubus_request *req, int ret)
{
    struct lua_ubus_context *ctx = container_of(req->ctx, struct lua_ubus_context, ctx);
    lua_State *co = ctx->co;

    if (ctx->data_cb == LUA_NOREF)
        return;

    lua_rawgeti(co, LUA_REGISTRYINDEX, ctx->data_cb);

    get_obj(co, &ubus_obj_key, ctx);
    lua_pushlightuserdata(co, req);
    lua_pushinteger(co, ret);

    lua_call(co, 3, 0);

    free(req);
}

static int lua_ubus_call(lua_State *L)
{
    struct lua_ubus_context *ctx = luaL_checkudata(L, 1, UBUS_CTX_MT);
    const char *path = luaL_checkstring(L, 2);
    const char *func = luaL_checkstring(L, 3);
    struct ubus_request *req;
    struct blob_buf buf = {};
    uint32_t id;
    int ret;

    if (ubus_lookup_id(&ctx->ctx, path, &id)) {
        lua_pushnil(L);
        lua_pushliteral(L, "not found");
        return 2;
    }

    req = calloc(1, sizeof(struct ubus_request));
    if (!req)
        return push_errno(L, errno);

    if (lua_arg_to_blob(L, 4, &buf)) {
        free(req);
        return 2;
    }

    ret = ubus_invoke_async(&ctx->ctx, id, func, buf.head, req);
    if (ret) {
        free(req);
        blob_buf_free(&buf);
        return push_ubus_error(L, ret);
    }

    req->data_cb = ubus_call_data_cb;
    req->complete_cb = ubus_call_complete_cb;
    ubus_complete_request_async(&ctx->ctx, req);

    blob_buf_free(&buf);

    lua_pushlightuserdata(L, req);

    return 1;
}

static int lua_ubus_send(lua_State *L)
{
    struct lua_ubus_context *ctx = luaL_checkudata(L, 1, UBUS_CTX_MT);
    const char *event = luaL_checkstring(L, 2);
    struct blob_buf buf = {};
    int ret;

    if (lua_arg_to_blob(L, 3, &buf))
        return 2;

    ret = ubus_send_event(&ctx->ctx, event, buf.head);

    blob_buf_free(&buf);

    if (ret)
        return push_ubus_error(L, ret);

    lua_pushboolean(L, true);

    return 1;
}

static int lua_ubus_reply(lua_State *L)
{
    struct lua_ubus_context *ctx = luaL_checkudata(L, 1, UBUS_CTX_MT);
    struct ubus_request_data *req = (struct ubus_request_data *)lua_checkludata(L, 2);
    struct blob_buf buf = {};
    int ret;

    if (lua_arg_to_blob(L, 3, &buf))
        return 2;

    ret = ubus_send_reply(&ctx->ctx, req, buf.head);

    blob_buf_free(&buf);

    if (ret)
        return push_ubus_error(L, ret);

    lua_pushboolean(L, true);

    return 1;
}

static void ubus_event_handler(struct ubus_context *ctx, struct ubus_event_handler *ev,
            const char *type, struct blob_attr *msg)
{
    struct lua_ubus_context *lctx = container_of(ctx, struct lua_ubus_context, ctx);
    lua_State *co = lctx->co;

    if (lctx->data_cb == LUA_NOREF)
        return;

    lua_rawgeti(co, LUA_REGISTRYINDEX, lctx->data_cb);

    get_obj(co, &ubus_obj_key, lctx);
    lua_pushlightuserdata(co, ev);
    lua_pushstring(co, type);
    blob_to_lua_table(co, blob_data(msg), blob_len(msg), false);

    lua_call(co, 4, 0);
}

static int lua_ubus_listen(lua_State *L)
{
    struct lua_ubus_context *ctx = luaL_checkudata(L, 1, UBUS_CTX_MT);
    const char *name = luaL_checkstring(L, 2);
    struct lua_ubus_event *lev;
    struct ubus_event_handler *ev;
    int ret;

    lev = calloc(1, sizeof(struct lua_ubus_event) + strlen(name) + 1);
    if (!lev)
        return push_errno(L, errno);

    ev = &lev->ev;
    ev->cb = ubus_event_handler;

    strcpy(lev->pattern, name);

    ret = ubus_register_event_handler(&ctx->ctx, ev, lev->pattern);
    if (ret) {
        free(lev);
        lua_pushnil(L);
        lua_pushstring(L, ubus_strerror(ret));
        return 2;
    }

    lua_ubus_ctx_save_obj(L, ev, LUA_UBUS_OBJ_EVENT);
    lua_pushlightuserdata(L, ev);

    return 1;
}

static int ubus_method_handler(struct ubus_context *ctx, struct ubus_object *obj,
        struct ubus_request_data *req, const char *method,
        struct blob_attr *msg)
{
    struct lua_ubus_context *lctx = container_of(ctx, struct lua_ubus_context, ctx);
    struct lua_ubus_object *lobj = container_of(obj, struct lua_ubus_object, object);
    struct ubus_request_data *dreq;
    lua_State *co = lctx->co;
    int ret = 0;

    if (lctx->data_cb == LUA_NOREF)
        return 0;

    lua_rawgeti(co, LUA_REGISTRYINDEX, lctx->data_cb);

    get_obj(co, &ubus_obj_key, lctx);
    lua_pushlightuserdata(co, lobj);

    dreq = malloc(sizeof(struct ubus_request_data));
    if (!dreq)
        luaL_error(co, "no mem");

    lua_pushstring(co, method);
    ubus_defer_request(ctx, req, dreq);
    lua_pushlightuserdata(co, dreq);

    blob_to_lua_table(co, blob_data(msg), blob_len(msg), false);

    lua_call(co, 5, 1);

    if (lua_isnumber(co, -1))
        ret = lua_tonumber(co, -1);

    lua_pop(co, 1);

    return ret;
}

static int lua_ubus_load_methods(lua_State *L, struct lua_ubus_object *lobj, int midx,
        struct blobmsg_policy **policy)
{
    struct ubus_method *m = lobj->methods + midx;
    const char *name = luaL_checkstring(L, -2);
    struct blobmsg_policy *p = *policy;
    int plen;

    m->handler = ubus_method_handler;
    m->name = strdup(name);
    if (!m->name)
        return luaL_error(L, "no mem");

    luaL_checktype(L, -1, LUA_TTABLE);

    plen = lua_gettablelen(L, -1);

    if (!plen) {
        m->policy = NULL;
        m->n_policy = 0;
        return 0;
    }

    m->policy = p;

    lua_pushnil(L);

    while (lua_next(L, -2) != 0) {
        name = luaL_checkstring(L, -2);
        p->name = strdup(name);
        if (!p->name)
            return luaL_error(L, "no mem");
        p->type = luaL_checkinteger(L, -1);
        lua_pop(L, 1);
        p++;
    }

    m->n_policy = plen;
    *policy = p;

    return 0;
}

static int lua_ubus_count_policies(lua_State *L, int index)
{
    int total = 0;

    index = lua_absindex(L, index);

    lua_pushnil(L);

    while (lua_next(L, index) != 0) {
        luaL_checktype(L, -1, LUA_TTABLE);
        total += lua_gettablelen(L, -1);
        lua_pop(L, 1);
    }

    return total;
}

static int lua_ubus_load_object(lua_State *L, struct lua_ubus_object *lobj, int mlen)
{
    struct blobmsg_policy **policy = &lobj->policy;
    int midx = 0;

    lua_pushnil(L);
    while (lua_next(L, 3)) {
        if (lua_ubus_load_methods(L, lobj, midx++, policy) < 0) {
            lua_pop(L, 2);
            return -1;
        }
        lua_pop(L, 1);
    }

    return 0;
}

static int lua_ubus_add(lua_State *L)
{
    struct lua_ubus_context *ctx = luaL_checkudata(L, 1, UBUS_CTX_MT);
    const char *name = luaL_checkstring(L, 2);
    struct lua_ubus_object *obj;
    int ret, mlen, plen;
    uint32_t id;

    luaL_checktype(L, 3, LUA_TTABLE);

    if (!ubus_lookup_id(&ctx->ctx, name, &id)) {
        lua_pushnil(L);
        lua_pushliteral(L, "object exists");
        return 2;
    }

    mlen = lua_gettablelen(L, 3);
    plen = lua_ubus_count_policies(L, 3);

    obj = calloc(1, sizeof(struct lua_ubus_object) +
            mlen * sizeof(struct ubus_method) +
            plen * sizeof(struct blobmsg_policy));
    if (!obj)
        return luaL_error(L, "no mem");

    obj->policy = (struct blobmsg_policy *)(obj->methods + mlen);

    obj->type.name = strdup(name);
    if (!obj->type.name)
        return luaL_error(L, "no mem");

    obj->type.methods = obj->methods;
    obj->type.n_methods = mlen;

    obj->object.name = obj->type.name;
    obj->object.type = &obj->type;
    obj->object.methods = obj->methods;
    obj->object.n_methods = mlen;

    ctx->co = L;

    if (lua_ubus_load_object(L, obj, mlen) < 0) {
        lua_ubus_free_object(obj);
        return push_errno(L, errno);
    }

    ret = ubus_add_object(&ctx->ctx, &obj->object);
    if (ret) {
        lua_ubus_free_object(obj);
        lua_pushnil(L);
        lua_pushstring(L, ubus_strerror(ret));
        return 2;
    }

    lua_ubus_ctx_save_obj(L, obj, LUA_UBUS_OBJ_OBJECT);
    lua_pushlightuserdata(L, obj);

    return 1;
}

static int ubus_subscriber_cb(struct ubus_context *ctx, struct ubus_object *obj,
            struct ubus_request_data *req,const char *method, struct blob_attr *msg)
{
    struct lua_ubus_context *lctx = container_of(ctx, struct lua_ubus_context, ctx);
    struct ubus_subscriber *s = container_of(obj, struct ubus_subscriber, obj);
    lua_State *co = lctx->co;

    if (lctx->data_cb == LUA_NOREF)
        return 0;

    lua_rawgeti(co, LUA_REGISTRYINDEX, lctx->data_cb);

    get_obj(co, &ubus_obj_key, lctx);
    lua_pushlightuserdata(co, s);
    lua_pushstring(co, method);
    blob_to_lua_table(co, blob_data(msg), blob_len(msg), false);

    lua_call(co, 4, 0);

    return 0;
}

static void ubus_subscriber_remove_cb(struct ubus_context *ctx,
        struct ubus_subscriber *sub, uint32_t id)
{
    struct lua_ubus_context *lctx = container_of(ctx, struct lua_ubus_context, ctx);

    if (sub->new_obj_cb)
        return;

    ubus_unregister_subscriber(&lctx->ctx, sub);
    lua_ubus_ctx_remove_obj(lctx->co, 0, lctx, sub);
    free(sub);
}

static bool ubus_subscriber_new_obj_cb(struct ubus_context *ctx,
        struct ubus_subscriber *sub, const char *path)
{
    struct lua_ubus_subscriber *lsub = container_of(sub,
            struct lua_ubus_subscriber, sub);

    return !strcmp(lsub->path, path);
}

static int lua_ubus_subscribe(lua_State *L)
{
    struct lua_ubus_context *ctx = luaL_checkudata(L, 1, UBUS_CTX_MT);
    const char *path = luaL_checkstring(L, 2);
    bool auto_sub = lua_toboolean(L, 3);
    struct lua_ubus_subscriber *lsub;
    struct ubus_subscriber *sub;
    uint32_t id;
    int ret;

    if (!auto_sub && ubus_lookup_id(&ctx->ctx, path, &id)) {
        lua_pushnil(L);
        lua_pushliteral(L, "not found");
        return 2;
    }

    lsub = calloc(1, sizeof(struct lua_ubus_subscriber) + strlen(path) + 1);
    if (!lsub)
        return push_errno(L, errno);

    sub = &lsub->sub;
    sub->cb = ubus_subscriber_cb;
    sub->remove_cb = ubus_subscriber_remove_cb;

    if (auto_sub) {
        strcpy(lsub->path, path);
        sub->new_obj_cb = ubus_subscriber_new_obj_cb;
    }

    ret = ubus_register_subscriber(&ctx->ctx, sub);
    if (ret) {
        free(lsub);
        lua_pushnil(L);
        lua_pushstring(L, ubus_strerror(ret));
        return 2;
    }

    if (!auto_sub) {
        ret = ubus_subscribe(&ctx->ctx, sub, id);
        if (ret) {
            ubus_unregister_subscriber(&ctx->ctx, sub);
            free(lsub);
            lua_pushnil(L);
            lua_pushstring(L, ubus_strerror(ret));
            return 2;
        }
    }

    lua_ubus_ctx_save_obj(L, lsub, LUA_UBUS_OBJ_SUBSCRIBER);
    lua_pushlightuserdata(L, sub);

    return 1;
}

static int lua_ubus_unsubscribe(lua_State *L)
{
    struct lua_ubus_context *ctx = luaL_checkudata(L, 1, UBUS_CTX_MT);
    struct ubus_subscriber *sub = (struct ubus_subscriber *)lua_checkludata(L, 2);

    if (!sub || !lua_ubus_ctx_has_obj(L, 1, NULL, sub)) {
        lua_pushnil(L);
        lua_pushliteral(L, "invalid subscriber");
        return 2;
    }

    ubus_unregister_subscriber(&ctx->ctx, sub);

    lua_ubus_ctx_remove_obj(L, 1, NULL, sub);

    free(sub);

    lua_pushboolean(L, true);

    return 1;
}

static int lua_ubus_notify(lua_State *L)
{
    struct lua_ubus_context *ctx = luaL_checkudata(L, 1, UBUS_CTX_MT);
    const char *method = luaL_checkstring(L, 3);
    struct lua_ubus_object *obj = (struct lua_ubus_object *)lua_checkludata(L, 2);
    struct blob_buf buf = {};
    int ret;

    if (lua_arg_to_blob(L, 4, &buf))
        return 2;

    ret = ubus_notify(&ctx->ctx, &obj->object, method, buf.head, -1);

    blob_buf_free(&buf);

    if (ret)
        return push_ubus_error(L, ret);

    lua_pushboolean(L, true);

    return 1;
}

static void lua_ubus_objects_cb(struct ubus_context *c, struct ubus_object_data *o, void *p)
{
    lua_State *L = (lua_State *)p;

    lua_pushinteger(L, o->id);
    lua_pushstring(L, o->path);
    lua_settable(L, -3);
}

static int lua_ubus_objects(lua_State *L)
{
    struct lua_ubus_context *ctx = luaL_checkudata(L, 1, UBUS_CTX_MT);
    int ret;

    lua_newtable(L);

    ret = ubus_lookup(&ctx->ctx, NULL, lua_ubus_objects_cb, L);
    if (ret != UBUS_STATUS_OK) {
        lua_pop(L, 1);
        lua_pushnil(L);
        lua_pushstring(L, ubus_strerror(ret));
        return 2;
    }

    return 1;
}

static void lua_ubus_signatures_cb(struct ubus_context *c, struct ubus_object_data *o, void *p)
{
    lua_State *L = (lua_State *)p;

    if (!o->signature)
        return;

    blob_to_lua_table(L, blob_data(o->signature), blob_len(o->signature), false);
}

static int lua_ubus_signatures(lua_State *L)
{
    struct lua_ubus_context *ctx = luaL_checkudata(L, 1, UBUS_CTX_MT);
    const char *path = luaL_checkstring(L, 2);
    int ret;

    lua_newtable(L);

    ret = ubus_lookup(&ctx->ctx, path, lua_ubus_signatures_cb, L);
    if (ret != UBUS_STATUS_OK) {
        lua_pop(L, 1);
        lua_pushnil(L);
        lua_pushstring(L, ubus_strerror(ret));
        return 2;
    }

    return 1;
}

static int lua_ubus_close(lua_State *L)
{
    struct lua_ubus_context *ctx = luaL_checkudata(L, 1, UBUS_CTX_MT);

    if (ctx->ctx.sock.eof)
        return 0;

    ubus_shutdown(&ctx->ctx);

    ctx->ctx.sock.eof = true;

    luaL_unref(L, LUA_REGISTRYINDEX, ctx->connection_lost_cb);
    luaL_unref(L, LUA_REGISTRYINDEX, ctx->data_cb);

    ctx->connection_lost_cb = LUA_NOREF;
    ctx->data_cb = LUA_NOREF;

    lua_getuservalue(L, 1);

    lua_pushnil(L);

    while (lua_next(L, -2) != 0) {
        int type = lua_tointeger(L, -1);

        if (type == LUA_UBUS_OBJ_OBJECT) {
            const struct lua_ubus_object *obj = lua_topointer(L, -2);
            lua_ubus_free_object(obj);
        } else {
            const void *obj = lua_topointer(L, -2);
            free((void *)obj);
        }

        lua_pop(L, 1);
    }

    return 0;
}

static void ubus_connection_lost(struct ubus_context *ctx)
{
    struct lua_ubus_context *lctx = container_of(ctx, struct lua_ubus_context, ctx);
    lua_State *co = lctx->co;

    if (lctx->connection_lost_cb == LUA_NOREF)
        return;

    lua_rawgeti(co, LUA_REGISTRYINDEX, lctx->connection_lost_cb);
    get_obj(co, &ubus_obj_key, lctx);

    lua_call(co, 1, 0);
}

static int lua_ubus_connect(lua_State *L)
{
    size_t size = sizeof(struct lua_ubus_context) + 1;
    const char *path = luaL_optstring(L, 1, NULL);
    struct lua_ubus_context *ctx;

    luaL_checktype(L, 2, LUA_TTABLE);

    if (getuid() > 0) {
        lua_pushnil(L);
        lua_pushliteral(L, "Operation not permitted, must be run as root");
        return 2;
    }

    if (path)
        size += strlen(path);

    ctx = lua_newuserdatauv(L, size, 1);
    lua_newtable(L);
    lua_setuservalue(L, -2);

    if (ubus_connect_ctx(&ctx->ctx, path)) {
        uloop_done();
        lua_pushnil(L);
        lua_pushliteral(L, "failed to connect to ubus");
        return 2;
    }

    uloop_done();

    luaL_setmetatable(L, UBUS_CTX_MT);

    set_obj(L, &ubus_obj_key, -1, ctx);

    if (path)
        strcpy(ctx->path, path);
    else
        ctx->path[0] = '\0';

    ctx->ctx.connection_lost = ubus_connection_lost;

    lua_getfield(L, 2, "on_connection_lost");
    luaL_checktype(L, -1, LUA_TFUNCTION);
    ctx->connection_lost_cb = luaL_ref(L, LUA_REGISTRYINDEX);

    lua_getfield(L, 2, "on_data");
    luaL_checktype(L, -1, LUA_TFUNCTION);
    ctx->data_cb = luaL_ref(L, LUA_REGISTRYINDEX);

    return 1;
}

static const struct luaL_Reg ubus_methods[] =  {
    {"getfd", lua_ubus_getfd},
    {"handle_event", lua_ubus_handle_event},
    {"reconnect", lua_ubus_reconnect},
    {"abort_request", lua_ubus_abort_request},
    {"complete_deferred_request", lua_ubus_complete_deferred_request},
    {"call", lua_ubus_call},
    {"send", lua_ubus_send},
    {"reply", lua_ubus_reply},
    {"listen", lua_ubus_listen},
    {"add", lua_ubus_add},
    {"subscribe", lua_ubus_subscribe},
    {"unsubscribe", lua_ubus_unsubscribe},
    {"notify", lua_ubus_notify},
    {"objects", lua_ubus_objects},
    {"signatures", lua_ubus_signatures},
    {"close", lua_ubus_close},
    {NULL, NULL}
};

static const struct luaL_Reg ubus_mt[] =  {
    {"__close", lua_ubus_close},
    {"__gc", lua_ubus_close},
    {NULL, NULL}
};

int luaopen_eco_internal_ubus(lua_State *L)
{
    creat_weak_table(L, "v", &ubus_obj_key);

    creat_metatable(L, UBUS_CTX_MT, ubus_mt, ubus_methods);

    lua_newtable(L);

    lua_add_constant(L, "STATUS_OK", UBUS_STATUS_OK);
    lua_add_constant(L, "STATUS_INVALID_COMMAND", UBUS_STATUS_INVALID_COMMAND);
    lua_add_constant(L, "STATUS_INVALID_ARGUMENT", UBUS_STATUS_INVALID_ARGUMENT);
    lua_add_constant(L, "STATUS_METHOD_NOT_FOUND", UBUS_STATUS_METHOD_NOT_FOUND);
    lua_add_constant(L, "STATUS_NOT_FOUND", UBUS_STATUS_NOT_FOUND);
    lua_add_constant(L, "STATUS_NO_DATA", UBUS_STATUS_NO_DATA);
    lua_add_constant(L, "STATUS_PERMISSION_DENIED", UBUS_STATUS_PERMISSION_DENIED);
    lua_add_constant(L, "STATUS_TIMEOUT", UBUS_STATUS_TIMEOUT);
    lua_add_constant(L, "STATUS_NOT_SUPPORTED", UBUS_STATUS_NOT_SUPPORTED);
    lua_add_constant(L, "STATUS_UNKNOWN_ERROR", UBUS_STATUS_UNKNOWN_ERROR);
    lua_add_constant(L, "STATUS_CONNECTION_FAILED", UBUS_STATUS_CONNECTION_FAILED);

    lua_add_constant(L, "ARRAY", BLOBMSG_TYPE_ARRAY);
    lua_add_constant(L, "TABLE", BLOBMSG_TYPE_TABLE);
    lua_add_constant(L, "STRING", BLOBMSG_TYPE_STRING);
    lua_add_constant(L, "INT64", BLOBMSG_TYPE_INT64);
    lua_add_constant(L, "INT32", BLOBMSG_TYPE_INT32);
    lua_add_constant(L, "INT16", BLOBMSG_TYPE_INT16);
    lua_add_constant(L, "INT8", BLOBMSG_TYPE_INT8);
    lua_add_constant(L, "DOUBLE", BLOBMSG_TYPE_DOUBLE);
    lua_add_constant(L, "BOOLEAN", BLOBMSG_TYPE_BOOL);

    lua_pushcfunction(L, lua_ubus_connect);
    lua_setfield(L, -2, "connect");

    lua_pushcfunction(L, lua_ubus_strerror);
    lua_setfield(L, -2, "strerror");

    return 1;
}
