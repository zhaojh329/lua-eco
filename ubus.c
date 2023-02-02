/*
 * MIT License
 *
 * Copyright (c) 2022 Jianhui Zhao <zhaojh329@gmail.com>
 *
 * Reference from: https://git.openwrt.org/?p=project/ubus.git;a=blob;f=lua/ubus.c
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

#include <libubus.h>
#include <fcntl.h>

#include "eco.h"

struct eco_ubus_context {
    struct ubus_context ctx;
    struct blob_buf buf;
    lua_State *L;
};

struct eco_ubus_request {
    struct ubus_request req;
    struct blob_attr *msg;
    int fd[2];
};

struct eco_ubus_event {
    struct ubus_event_handler e;
};

struct eco_ubus_object {
    struct ubus_object object;
    struct ubus_object_type type;
    struct ubus_method methods[0];
};

#define ECO_UBUS_CTX_MT "eco{ubus-ctx}"
#define ECO_UBUS_REQ_MT "eco{ubus-req}"

static const char *obj_registry = "eco.ubus{obj}";

static void lua_table_to_blob(lua_State *L, int index, struct blob_buf *b, bool is_array)
{
    void *c;

    if (!lua_istable(L, index))
        return;

    for (lua_pushnil(L); lua_next(L, index); lua_pop(L, 2)) {
        const char *key;

        lua_pushvalue(L, -2);
        lua_insert(L, -2);

        key = is_array ? NULL : lua_tostring(L, -2);

        switch (lua_type(L, -1)) {
        case LUA_TBOOLEAN:
            blobmsg_add_u8(b, key, (uint8_t)lua_toboolean(L, -1));
            break;
#ifdef LUA_TINT
        case LUA_TINT:
#endif
        case LUA_TNUMBER:
            if ((uint64_t)lua_tonumber(L, -1) != lua_tonumber(L, -1))
                blobmsg_add_double(b, key, lua_tonumber(L, -1));
            else
                blobmsg_add_u32(b, key, (uint32_t)lua_tointeger(L, -1));
            break;

        case LUA_TSTRING:
        case LUA_TUSERDATA:
        case LUA_TLIGHTUSERDATA:
            blobmsg_add_string(b, key, lua_tostring(L, -1));
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
        lua_pushinteger(L, be16_to_cpu(*(uint16_t *)data));
        break;

    case BLOBMSG_TYPE_INT32:
        lua_pushint(L, be32_to_cpu(*(uint32_t *)data));
        break;

    case BLOBMSG_TYPE_INT64:
        lua_pushuint(L, (double) be64_to_cpu(*(uint64_t *)data));
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

static void eco_push_ubus_ctx(lua_State *L, struct eco_ubus_context *ctx)
{
    lua_pushlightuserdata(L, &obj_registry);
    lua_rawget(L, LUA_REGISTRYINDEX);

    lua_pushlightuserdata(L, ctx);
    lua_rawget(L, -2);

    lua_remove(L, -2);
}

static int eco_ubus_close(lua_State *L)
{
    struct eco_ubus_context *ctx = luaL_checkudata(L, 1, ECO_UBUS_CTX_MT);

    if (ctx->ctx.sock.eof)
        return 0;

    ubus_shutdown(&ctx->ctx);

    ctx->ctx.sock.eof = true;

    lua_pushlightuserdata(L, &obj_registry);
    lua_rawget(L, LUA_REGISTRYINDEX);;

    lua_pushlightuserdata(L, ctx);
    lua_pushnil(L);
    lua_rawset(L, -3);

    lua_pop(L, 1);

    return 0;
}

static int eco_ubus_req_wait_fd(lua_State *L)
{
    struct eco_ubus_request *req = luaL_checkudata(L, 1, ECO_UBUS_REQ_MT);
    lua_pushinteger(L, req->fd[0]);
    return 1;
}

static int eco_ubus_req_parse(lua_State *L)
{
    struct eco_ubus_request *req = luaL_checkudata(L, 1, ECO_UBUS_REQ_MT);

    blob_to_lua_table(L, blob_data(req->msg), blob_len(req->msg), false);
    return 1;
}

static int eco_ubus_req_close(lua_State *L)
{
    struct eco_ubus_request *req = luaL_checkudata(L, 1, ECO_UBUS_REQ_MT);

    if (req->fd[0] > -1) {
        close(req->fd[0]);
        close(req->fd[1]);
        req->fd[0] = -1;
    }

    if (req->msg) {
        free(req->msg);
        req->msg = NULL;
    }

    return 0;
}

static int eco_ubus_req_gc(lua_State *L)
{
    return eco_ubus_req_close(L);
}

static const struct luaL_Reg ubus_req_methods[] = {
    {"wait_fd", eco_ubus_req_wait_fd},
    {"parse", eco_ubus_req_parse},
    {"close", eco_ubus_req_close},
    {"__gc", eco_ubus_req_gc},
    {NULL, NULL}
};

static void eco_ubus_call_data_cb(struct ubus_request *req, int type, struct blob_attr *msg)
{
    struct eco_ubus_request *ereq = container_of(req, struct eco_ubus_request, req);
    ereq->msg = blob_memdup(msg);
}

static void eco_ubus_call_complete_cb(struct ubus_request *req, int ret)
{
    struct eco_ubus_request *ereq = container_of(req, struct eco_ubus_request, req);

    if (write(ereq->fd[1], "q", 1));
}

static int eco_ubus_call(lua_State *L)
{
    struct eco_ubus_context *ctx = luaL_checkudata(L, 1, ECO_UBUS_CTX_MT);
    const char *path = luaL_checkstring(L, 2);
    const char *func = luaL_checkstring(L, 3);
    struct eco_ubus_request *req;
    uint32_t id;
    int ret;

    if (ubus_lookup_id(&ctx->ctx, path, &id)) {
        lua_pushnil(L);
        lua_pushliteral(L, "not found");
        return 2;
    }

    blob_buf_init(&ctx->buf, 0);
    lua_table_to_blob(L, 4, &ctx->buf, false);

    req = lua_newuserdata(L, sizeof(struct eco_ubus_request));
    eco_new_metatable(L, ECO_UBUS_REQ_MT, ubus_req_methods);
    lua_setmetatable(L, -2);

    req->fd[0] = -1;
    req->fd[1] = -1;
    req->msg = NULL;

    if (pipe2(req->fd, O_CLOEXEC | O_NONBLOCK)) {
        lua_pushnil(L);
        lua_pushstring(L, strerror(errno));
        return 2;
    }

    ret = ubus_invoke_async(&ctx->ctx, id, func, ctx->buf.head, &req->req);
    if (ret) {
        lua_pushnil(L);
        lua_pushstring(L, ubus_strerror(ret));
        return 2;
    }

    req->req.data_cb = eco_ubus_call_data_cb;
    req->req.complete_cb = eco_ubus_call_complete_cb;
    ubus_complete_request_async(&ctx->ctx, &req->req);

    return 1;
}

static int eco_ubus_send(lua_State *L)
{
    struct eco_ubus_context *ctx = luaL_checkudata(L, 1, ECO_UBUS_CTX_MT);
    const char *event = luaL_checkstring(L, 2);

    luaL_checktype(L, 3, LUA_TTABLE);
    blob_buf_init(&ctx->buf, 0);

    lua_table_to_blob(L, 3, &ctx->buf, false);

    ubus_send_event(&ctx->ctx, event, ctx->buf.head);

    return 0;
}

static void eco_ubus_event_handler(struct ubus_context *ctx, struct ubus_event_handler *ev,
            const char *type, struct blob_attr *msg)
{
    struct eco_ubus_context *c = container_of(ctx, struct eco_ubus_context, ctx);
    struct eco_ubus_event *e = container_of(ev, struct eco_ubus_event, e);
    lua_State *L = c->L;

    lua_pushnil(L);

    eco_push_ubus_ctx(L, c);
    lua_getuservalue(L, -1);

    lua_pushlightuserdata(L, e);
    lua_rawget(L, -2);

    lua_getuservalue(L, -1);

    lua_rawgeti(L, -1, 1);

    lua_replace(L, -6);

    lua_settop(L, -5);

    lua_pushstring(L, type);

    blob_to_lua_table(L, blob_data(msg), blob_len(msg), false);

    lua_call(L, 2, 0);
}

static int eco_ubus_listen(lua_State *L)
{
    struct eco_ubus_context *ctx = luaL_checkudata(L, 1, ECO_UBUS_CTX_MT);
    const char *event = luaL_checkstring(L, 2);
    struct eco_ubus_event *e;
    int ret;

    luaL_checktype(L, 3, LUA_TFUNCTION);

    e = lua_newuserdata(L, sizeof(struct eco_ubus_event));
    lua_newtable(L);
    lua_pushvalue(L, 3);
    lua_rawseti(L, -2, 1);
    lua_setuservalue(L, -2);

    memset(e, 0, sizeof(struct eco_ubus_event));

    e->e.cb = eco_ubus_event_handler;

    ret = ubus_register_event_handler(&ctx->ctx, &e->e, event);
    if (ret) {
        lua_pushnil(L);
        lua_pushstring(L, ubus_strerror(ret));
        return 2;
    }

    eco_push_ubus_ctx(L, ctx);
    lua_getuservalue(L, -1);

    lua_pushlightuserdata(L, e);
    lua_pushvalue(L, -4);
    lua_rawset(L, -3);

    lua_settop(L, -3);

    return 1;
}

static int ubus_method_handler(struct ubus_context *ctx, struct ubus_object *obj,
        struct ubus_request_data *req, const char *method,
        struct blob_attr *msg)
{
    struct eco_ubus_context *c = container_of(ctx, struct eco_ubus_context, ctx);
    struct eco_ubus_object *o = container_of(obj, struct eco_ubus_object, object);
    lua_State *L = c->L;
    int rv = 0;

    lua_pushnil(L);

    eco_push_ubus_ctx(L, c);
    lua_getuservalue(L, -1);

    lua_pushlightuserdata(L, o);
    lua_rawget(L, -2);

    lua_getuservalue(L, -1);
    lua_getfield(L, -1, method);

    lua_replace(L, -6);
    lua_settop(L, -5);

    lua_pushlightuserdata(L, req);

    blob_to_lua_table(L, blob_data(msg), blob_len(msg), false);

    lua_call(L, 2, 1);

    if (lua_isnumber(L, -1))
		rv = lua_tonumber(L, -1);

    return rv;
}

static int eco_ubus_load_methods(lua_State *L, struct ubus_method *m)
{
    const char *name = lua_tostring(L, -2);
    struct blobmsg_policy *p;
    int pidx = 0, plen;

    /* store function to uservalue */
    lua_rawgeti(L, -1, 1);
    if ((lua_type(L, -1) != LUA_TFUNCTION)) {
        lua_pop(L, 1);
        return 1;
    }
    lua_setfield(L, 5, name);

    m->handler = ubus_method_handler;
    m->name = name;

    /* get the policy table */
    lua_rawgeti(L, -1, 2);

    if ((lua_type(L, -1) != LUA_TTABLE) || lua_rawlen(L, -1)) {
        lua_pop(L, 1);
        return 0;
    }

    plen = lua_gettablelen(L, -1);

    /* exit if policy table is empty */
    if (!plen) {
        lua_pop(L, 1);
        return 0;
    }

    /* setup the policy pointers */
    p = calloc(plen, sizeof(struct blobmsg_policy));
    if (!p)
        return 1;

    m->policy = p;
    lua_pushnil(L);
    while (lua_next(L, -2) != 0) {
        int val = lua_tointeger(L, -1);

        /* check if the policy is valid */
        if ((lua_type(L, -2) != LUA_TSTRING) ||
                (lua_type(L, -1) != LUA_TNUMBER) ||
                (val < 0) ||
                (val > BLOBMSG_TYPE_LAST)) {
            lua_pop(L, 1);
            continue;
        }
        p[pidx].name = lua_tostring(L, -2);
        p[pidx].type = val;
        lua_pop(L, 1);
        pidx++;
    }

    m->n_policy = pidx;
    lua_pop(L, 1);

    return 0;
}

static void eco_ubus_load_object(lua_State *L, struct eco_ubus_object *o)
{
    struct ubus_object *obj = &o->object;
    struct ubus_object_type *type = &o->type;
    struct ubus_method *methods = o->methods;
    const char *name = lua_tostring(L, 2);
    int midx = 0;

    obj->name = name;
    obj->methods = methods;

    type->name = name;
    type->methods = methods;

    obj->type = type;

    lua_pushnil(L);
    while (lua_next(L, 3)) {
        if ((lua_type(L, -2) != LUA_TSTRING) ||
            (lua_type(L, -1) != LUA_TTABLE) ||
            !lua_rawlen(L, -1)) {
            lua_pop(L, 1);
            continue;
        }

        if (!eco_ubus_load_methods(L, methods + midx))
            midx++;
        lua_pop(L, 1);
    }

    type->n_methods = obj->n_methods = midx;
}

static int eco_ubus_add(lua_State *L)
{
    struct eco_ubus_context *ctx = luaL_checkudata(L, 1, ECO_UBUS_CTX_MT);
    struct eco_ubus_object *o;
    int ret, mlen;

    luaL_checkstring(L, 2);
    luaL_checktype(L, 3, LUA_TTABLE);

    mlen = lua_gettablelen(L, 3);

    o = lua_newuserdata(L, sizeof(struct eco_ubus_object) + mlen * sizeof(struct ubus_method));
    memset(o, 0, sizeof(struct eco_ubus_object) + mlen * sizeof(struct ubus_method));

    lua_newtable(L);

    eco_ubus_load_object(L, o);

    lua_setuservalue(L, -2);

    ret = ubus_add_object(&ctx->ctx, &o->object);
    if (ret) {
        lua_pushnil(L);
        lua_pushstring(L, ubus_strerror(ret));
        return 2;
    }

    eco_push_ubus_ctx(L, ctx);
    lua_getuservalue(L, -1);

    lua_pushlightuserdata(L, o);
    lua_pushvalue(L, -4);
    lua_rawset(L, -3);

    lua_settop(L, -3);

    return 1;
}

static int eco_ubus_reply(lua_State *L)
{
    struct eco_ubus_context *ctx = luaL_checkudata(L, 1, ECO_UBUS_CTX_MT);
    struct ubus_request_data *req = lua_touserdata(L, 2);

    luaL_checktype(L, 3, LUA_TTABLE);
    blob_buf_init(&ctx->buf, 0);

    lua_table_to_blob(L, 3, &ctx->buf, false);

    ubus_send_reply(&ctx->ctx, req, ctx->buf.head);

    return 0;
}

static int eco_ubus_connect(lua_State *L)
{
    struct eco_context *eco = luaL_checkudata(L, 1, ECO_CTX_MT);
    const char *sock = luaL_optstring(L, 2, NULL);
    struct eco_ubus_context *ctx;

    if (getuid() > 0) {
        lua_pushnil(L);
        lua_pushliteral(L, "Operation not permitted, must be run as root");
        return 2;
    }

    ctx = lua_newuserdata(L, sizeof(struct eco_ubus_context));
    memset(ctx, 0, sizeof(struct eco_ubus_context));

    ctx->L = eco->L;

    if (ubus_connect_ctx(&ctx->ctx, sock)) {
        lua_pushnil(L);
        lua_pushliteral(L, "Failed to connect to ubus");
        return 2;
    }

    lua_pushvalue(L, lua_upvalueindex(1));
    lua_setmetatable(L, -2);

    lua_newtable(L);
    lua_setuservalue(L, -2);

    lua_pushlightuserdata(L, &obj_registry);
    lua_rawget(L, LUA_REGISTRYINDEX);
    lua_pushlightuserdata(L, ctx);
    lua_pushvalue(L, -3);
    lua_rawset(L, -3);
    lua_pop(L, 1);

    return 1;
}

static int eco_ubus_getfd(lua_State *L)
{
    struct eco_ubus_context *ctx = luaL_checkudata(L, 1, ECO_UBUS_CTX_MT);
    lua_pushinteger(L, ctx->ctx.sock.fd);
    return 1;
}

static int eco_ubus_process_msg(lua_State *L)
{
    struct eco_ubus_context *ctx = luaL_checkudata(L, 1, ECO_UBUS_CTX_MT);
    ubus_handle_event(&ctx->ctx);
    return 0;
}

static const struct luaL_Reg ubus_methods[] =  {
    {"call", eco_ubus_call},
    {"send", eco_ubus_send},
    {"listen", eco_ubus_listen},
    {"add", eco_ubus_add},
    {"reply", eco_ubus_reply},
    {"close", eco_ubus_close},
    {"getfd", eco_ubus_getfd},
    {"process_msg", eco_ubus_process_msg},
    {NULL, NULL}
};

int luaopen_eco_core_ubus(lua_State *L)
{
    lua_pushlightuserdata(L, &obj_registry);
    lua_newtable(L);
    lua_createtable(L, 0, 1);
    lua_pushliteral(L, "v");
    lua_setfield(L, -2, "__mode");
    lua_setmetatable(L, -2);
    lua_rawset(L, LUA_REGISTRYINDEX);

    lua_newtable(L);

    lua_add_constant(L, "ARRAY", BLOBMSG_TYPE_ARRAY);
    lua_add_constant(L, "TABLE", BLOBMSG_TYPE_TABLE);
    lua_add_constant(L, "STRING", BLOBMSG_TYPE_STRING);
    lua_add_constant(L, "INT64", BLOBMSG_TYPE_INT64);
    lua_add_constant(L, "INT32", BLOBMSG_TYPE_INT32);
    lua_add_constant(L, "INT16", BLOBMSG_TYPE_INT16);
    lua_add_constant(L, "INT8", BLOBMSG_TYPE_INT8);
    lua_add_constant(L, "DOUBLE", BLOBMSG_TYPE_DOUBLE);
    lua_add_constant(L, "BOOLEAN", BLOBMSG_TYPE_BOOL);

    eco_new_metatable(L, ECO_UBUS_CTX_MT, ubus_methods);
    lua_pushcclosure(L, eco_ubus_connect, 1);
    lua_setfield(L, -2, "connect");

    return 1;
}
