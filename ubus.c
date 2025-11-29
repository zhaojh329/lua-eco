/* SPDX-License-Identifier: MIT */
/*
 * Author: Jianhui Zhao <zhaojh329@gmail.com>
 */

#include <libubus.h>

#include "eco.h"

#define UBUS_CTX_MT "struct ubus_context *"
#define UBUS_REQ_MT "struct lua_ubus_request *"

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
    struct ubus_method *methods;
};

static void lua_table_to_blob(lua_State *L, int index, struct blob_buf *b, bool is_array)
{
    void *c;

    if (!lua_istable(L, index))
        return;

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
                lua_table_to_blob(L, lua_gettop(L), b, true);
                blobmsg_close_array(b, c);
            } else {
                c = blobmsg_open_table(b, key);
                lua_table_to_blob(L, lua_gettop(L), b, false);
                blobmsg_close_table(b, c);
            }
            break;
        }
    }
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

static int lua_ubus_reconnect(lua_State *L)
{
    struct lua_ubus_context *ctx = luaL_checkudata(L, 1, UBUS_CTX_MT);
    const char *path = ctx->path[0] ? ctx->path : NULL;

    if (ubus_reconnect(&ctx->ctx, path))
        lua_pushnil(L);
    else
        lua_pushinteger(L, ctx->ctx.sock.fd);

    return 1;
}

static int lua_ubus_abort_request(lua_State *L)
{
    struct lua_ubus_context *ctx = luaL_checkudata(L, 1, UBUS_CTX_MT);
    struct ubus_request *req = luaL_checkudata(L, 2, UBUS_REQ_MT);
    ubus_abort_request(&ctx->ctx, req);
    return 0;
}

static int lua_ubus_complete_deferred_request(lua_State *L)
{
    struct lua_ubus_context *ctx = luaL_checkudata(L, 1, UBUS_CTX_MT);
    struct ubus_request_data *req = (struct ubus_request_data *)lua_topointer(L, 2);
    int ret = luaL_checkinteger(L, 3);
    ubus_complete_deferred_request(&ctx->ctx, req, ret);
    return 0;
}

static void ubus_call_data_cb(struct ubus_request *req, int type, struct blob_attr *msg)
{
    struct lua_ubus_context *ctx = container_of(req->ctx, struct lua_ubus_context, ctx);
    lua_State *co = ctx->co;

    lua_pushlightuserdata(co, req);
    blob_to_lua_table(co, blob_data(msg), blob_len(msg), false);
    lua_call(co, 2, 0);
}

static void ubus_call_complete_cb(struct ubus_request *req, int ret)
{
    struct lua_ubus_context *ctx = container_of(req->ctx, struct lua_ubus_context, ctx);
    lua_State *co = ctx->co;

    lua_pushlightuserdata(co, req);
    lua_pushinteger(co, ret);
    lua_call(co, 2, 0);
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

    if (!lua_isnil(L, 4))
        luaL_checktype(L, 4, LUA_TTABLE);

    luaL_checktype(L, 5, LUA_TFUNCTION);
    luaL_checktype(L, 6, LUA_TFUNCTION);

    if (ubus_lookup_id(&ctx->ctx, path, &id)) {
        lua_pushnil(L);
        lua_pushliteral(L, "not found");
        return 2;
    }

    req = lua_newuserdata(L, sizeof(struct ubus_request));
    if (!req) {
        lua_pushnil(L);
        lua_pushstring(L, strerror(errno));
        return 2;
    }
    luaL_setmetatable(L, UBUS_REQ_MT);

    blob_buf_init(&buf, 0);

    lua_table_to_blob(L, 4, &buf, false);

    ret = ubus_invoke_async(&ctx->ctx, id, func, buf.head, req);
    if (ret) {
        blob_buf_free(&buf);
        lua_pushnil(L);
        lua_pushstring(L, ubus_strerror(ret));
        return 2;
    }

    req->data_cb = ubus_call_data_cb;
    req->complete_cb = ubus_call_complete_cb;
    ubus_complete_request_async(&ctx->ctx, req);

    blob_buf_free(&buf);

    return 1;
}

static int lua_ubus_send(lua_State *L)
{
    struct lua_ubus_context *ctx = luaL_checkudata(L, 1, UBUS_CTX_MT);
    const char *event = luaL_checkstring(L, 2);
    struct blob_buf buf = {};

    luaL_checktype(L, 3, LUA_TTABLE);

    blob_buf_init(&buf, 0);

    lua_table_to_blob(L, 3, &buf, false);

    ubus_send_event(&ctx->ctx, event, buf.head);

    blob_buf_free(&buf);

    return 0;
}

static int lua_ubus_reply(lua_State *L)
{
    struct lua_ubus_context *ctx = luaL_checkudata(L, 1, UBUS_CTX_MT);
    struct ubus_request_data *req = (struct ubus_request_data *)lua_topointer(L, 2);
    struct blob_buf buf = {};

    luaL_checktype(L, 3, LUA_TTABLE);

    blob_buf_init(&buf, 0);

    lua_table_to_blob(L, 3, &buf, false);

    ubus_send_reply(&ctx->ctx, req, buf.head);

    blob_buf_free(&buf);

    return 0;
}

static void ubus_event_handler(struct ubus_context *ctx, struct ubus_event_handler *ev,
            const char *type, struct blob_attr *msg)
{
    struct lua_ubus_context *lctx = container_of(ctx, struct lua_ubus_context, ctx);
    lua_State *co = lctx->co;

    lua_rawgeti(co, LUA_REGISTRYINDEX, lctx->data_cb);

    lua_pushlightuserdata(co, ev);
    lua_pushstring(co, type);
    blob_to_lua_table(co, blob_data(msg), blob_len(msg), false);

    lua_call(co, 3, 0);
}

static int lua_ubus_listen(lua_State *L)
{
    struct lua_ubus_context *ctx = luaL_checkudata(L, 1, UBUS_CTX_MT);
    const char *name = luaL_checkstring(L, 2);
    struct ubus_event_handler *ev;
    int ret;

    ev = calloc(1, sizeof(struct ubus_event_handler));
    ev->cb = ubus_event_handler;

    ret = ubus_register_event_handler(&ctx->ctx, ev, name);
    if (ret) {
        lua_pushnil(L);
        lua_pushstring(L, ubus_strerror(ret));
        return 2;
    }

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

    lua_rawgeti(co, LUA_REGISTRYINDEX, lctx->data_cb);

    lua_pushlightuserdata(co, lobj);

    dreq = malloc(sizeof(struct ubus_request_data));
    if (!dreq)
        luaL_error(co, "no mem");

    lua_pushstring(co, method);
    ubus_defer_request(ctx, req, dreq);
    lua_pushlightuserdata(co, dreq);

    blob_to_lua_table(co, blob_data(msg), blob_len(msg), false);

    lua_call(co, 4, 1);

    if (lua_isnumber(co, -1))
        ret = lua_tonumber(co, -1);

    lua_pop(co, 1);

    return ret;
}

static int lua_ubus_load_methods(lua_State *L, struct lua_ubus_object *lobj, int midx)
{
    struct ubus_method *m = lobj->methods + midx;
    struct blobmsg_policy *p;
    int plen;

    m->handler = ubus_method_handler;
    m->name = luaL_checkstring(L, -2);

    luaL_checktype(L, -1, LUA_TTABLE);

    plen = lua_gettablelen(L, -1);

    lobj->policy = calloc(plen, sizeof(struct blobmsg_policy));
    if (!lobj->policy)
        return luaL_error(L, "no mem");

    p = lobj->policy;

    lua_pushnil(L);

    while (lua_next(L, -2) != 0) {
        p->name = luaL_checkstring(L, -2);
        p->type = luaL_checkinteger(L, -1);
        lua_pop(L, 1);
        p++;
    }

    m->policy = lobj->policy;
    m->n_policy = plen;

    return 0;
}

static void lua_ubus_load_object(lua_State *L, struct lua_ubus_object *lobj, int mlen)
{
    int midx = 0;

    lua_pushnil(L);
    while (lua_next(L, 3)) {
        lua_ubus_load_methods(L, lobj, midx++);
        lua_pop(L, 1);
    }
}

static int lua_ubus_add(lua_State *L)
{
    struct lua_ubus_context *ctx = luaL_checkudata(L, 1, UBUS_CTX_MT);
    const char *name = luaL_checkstring(L, 2);
    struct lua_ubus_object *obj;
    int ret, mlen;

    luaL_checktype(L, 3, LUA_TTABLE);

    obj = calloc(1, sizeof(struct lua_ubus_object));

    mlen = lua_gettablelen(L, 3);

    obj->methods = calloc(mlen, sizeof(struct ubus_method));
    if (!obj->methods)
        return luaL_error(L, "no mem");

    obj->type.name = name;
    obj->type.methods = obj->methods;
    obj->type.n_methods = mlen;

    obj->object.name = name;
    obj->object.type = &obj->type;
    obj->object.methods = obj->methods;
    obj->object.n_methods = mlen;

    ctx->co = L;

    lua_ubus_load_object(L, obj, mlen);

    ret = ubus_add_object(&ctx->ctx, &obj->object);
    if (ret) {
        lua_pushnil(L);
        lua_pushstring(L, ubus_strerror(ret));
        return 2;
    }

    lua_pushlightuserdata(L, obj);

    return 1;
}

static int ubus_subscriber_cb(struct ubus_context *ctx, struct ubus_object *obj,
            struct ubus_request_data *req,const char *method, struct blob_attr *msg)
{
    struct lua_ubus_context *lctx = container_of(ctx, struct lua_ubus_context, ctx);
    struct ubus_subscriber *s = container_of(obj, struct ubus_subscriber, obj);
    lua_State *co = lctx->co;

    lua_rawgeti(co, LUA_REGISTRYINDEX, lctx->data_cb);

    lua_pushlightuserdata(co, s);
    lua_pushstring(co, method);
    blob_to_lua_table(co, blob_data(msg), blob_len(msg), false);

    lua_call(co, 3, 0);

    return 0;
}

static int lua_ubus_subscribe(lua_State *L)
{
    struct lua_ubus_context *ctx = luaL_checkudata(L, 1, UBUS_CTX_MT);
    const char *path = luaL_checkstring(L, 2);
    struct ubus_subscriber *sub;
    uint32_t id;
    int ret;

    if (ubus_lookup_id(&ctx->ctx, path, &id)) {
        lua_pushnil(L);
        lua_pushliteral(L, "not found");
        return 2;
    }

    sub = calloc(1, sizeof(struct ubus_subscriber));
    sub->cb = ubus_subscriber_cb;

    ret = ubus_register_subscriber(&ctx->ctx, sub);
    if (ret) {
        lua_pushnil(L);
        lua_pushstring(L, ubus_strerror(ret));
        return 2;
    }

    ret = ubus_subscribe(&ctx->ctx, sub, id);
    if (ret) {
        lua_pushnil(L);
        lua_pushstring(L, ubus_strerror(ret));
        return 2;
    }

    lua_pushlightuserdata(L, sub);

    return 1;
}

static int lua_ubus_notify(lua_State *L)
{
    struct lua_ubus_context *ctx = luaL_checkudata(L, 1, UBUS_CTX_MT);
    struct lua_ubus_object *obj = (struct lua_ubus_object *)lua_topointer(L, 2);
    const char *method = luaL_checkstring(L, 3);
    struct blob_buf buf = {};

    luaL_checktype(L, 4, LUA_TTABLE);

    blob_buf_init(&buf, 0);

    lua_table_to_blob(L, 4, &buf, false);

    ubus_notify(&ctx->ctx, &obj->object, method, buf.head, -1);

    blob_buf_free(&buf);

    return 0;
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

    return 0;
}

static void ubus_connection_lost(struct ubus_context *ctx)
{
    struct lua_ubus_context *lctx = container_of(ctx, struct lua_ubus_context, ctx);
    lua_State *co = lctx->co;

    lua_rawgeti(co, LUA_REGISTRYINDEX, lctx->connection_lost_cb);
    lua_call(co, 0, 0);
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

    ctx = lua_newuserdata(L, size);

    if (ubus_connect_ctx(&ctx->ctx, path)) {
        uloop_done();
        lua_pushnil(L);
        lua_pushliteral(L, "failed to connect to ubus");
        return 2;
    }

    uloop_done();

    luaL_setmetatable(L, UBUS_CTX_MT);

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
    creat_metatable(L, UBUS_CTX_MT, ubus_mt, ubus_methods);
    creat_metatable(L, UBUS_REQ_MT, NULL, NULL);

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
