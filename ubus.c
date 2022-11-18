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

#include "eco.h"

struct eco_ubus_context {
    struct eco_context *ctx;
    struct ubus_context *u;
    struct blob_buf buf;
    struct ev_io ior;
    double timeout;
};

struct eco_ubus_request {
    struct eco_ubus_context *ctx;
    struct ubus_request req;
    struct ev_timer tmr;
    lua_State *co;
    bool has_data;
};

struct eco_ubus_event {
    struct ubus_event_handler e;
    lua_State *L;
    int r;
};

struct eco_ubus_object {
    struct ubus_object o;
    lua_State *L;
    int r;
};

static char eco_ubus_event_key;
static char eco_ubus_method_key;

static void lua_table_to_blob(lua_State *L, int index, struct blob_buf *b, bool is_array)
{
    void *c;

    if (!lua_istable(L, index))
        return;

    for (lua_pushnil(L); lua_next(L, index); lua_pop(L, 1)) {
        const char *key = is_array ? NULL : lua_tostring(L, -2);

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
            if (lua_table_is_array(L)) {
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

    switch (blob_id(attr))
    {
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

static void eco_ubus_read_cb(struct ev_loop *loop, ev_io *w, int revents)
{
    struct eco_ubus_context *ctx = container_of(w, struct eco_ubus_context, ior);
    ubus_handle_event(ctx->u);
}

static int eco_ubus_close(lua_State *L)
{
    struct eco_ubus_context *ctx = lua_touserdata(L, 1);

    if (!ctx->u)
        return 0;

    ev_io_stop(ctx->ctx->loop, &ctx->ior);

    ubus_free(ctx->u);
    ctx->u = NULL;

    return 0;
}

static int eco_ubus_gc(lua_State *L)
{
    return eco_ubus_close(L);
}

static void eco_ubus_objects_cb(struct ubus_context *c, struct ubus_object_data *o, void *p)
{
    lua_State *L = p;

    lua_pushstring(L, o->path);
    lua_rawseti(L, -2, lua_rawlen(L, -2) + 1);
}

static int eco_ubus_objects(lua_State *L)
{
    struct eco_ubus_context *ctx = lua_touserdata(L, 1);
    int res;

    lua_newtable(L);

    res = ubus_lookup(ctx->u, NULL, eco_ubus_objects_cb, L);
    if (res) {
        lua_pop(L, 1);
        lua_pushnil(L);
        lua_pushstring(L, ubus_strerror(res));
        return 2;
    }

    return 1;
}

static void ubus_lua_signatures_cb(struct ubus_context *c, struct ubus_object_data *o, void *p)
{
    lua_State *L = p;

    if (!o->signature)
        return;

    blob_to_lua_table(L, blob_data(o->signature), blob_len(o->signature), false);
}

static int eco_ubus_signatures(lua_State *L)
{
    struct eco_ubus_context *ctx = lua_touserdata(L, 1);
    const char *path = luaL_checkstring(L, 2);
    int res;

    res = ubus_lookup(ctx->u, path, ubus_lua_signatures_cb, L);
    if (res) {
        lua_pop(L, 1);
        lua_pushnil(L);
        lua_pushstring(L, ubus_strerror(res));
        return 2;
    }

    return 1;
}

static int eco_ubus_settimeout(lua_State *L)
{
    struct eco_ubus_context *ctx = lua_touserdata(L, 1);

    ctx->timeout = lua_tonumber(L, 2);
    return 0;
}

static void eco_ubus_call_timer_cb(struct ev_loop *loop, ev_timer *w, int revents)
{
    struct eco_ubus_request *req = container_of(w, struct eco_ubus_request, tmr);
    lua_State *L = req->ctx->ctx->L;
    lua_State *co = req->co;

    ubus_abort_request(req->ctx->u, &req->req);

    lua_pushlightuserdata(L, req);
    lua_pushnil(L);
    lua_rawset(L, LUA_REGISTRYINDEX);

    lua_pushnil(co);
    lua_pushliteral(co, "timeout");

    eco_resume(L, co, 2);
}

static void eco_ubus_call_data_cb(struct ubus_request *req, int type, struct blob_attr *msg)
{
    struct eco_ubus_request *eco_req = container_of(req, struct eco_ubus_request, req);
    lua_State *co = eco_req->co;

    blob_to_lua_table(co, blob_data(msg), blob_len(msg), false);

    eco_req->has_data = true;
}

static void eco_ubus_call_complete_cb(struct ubus_request *req, int ret)
{
    struct eco_ubus_request *eco_req = container_of(req, struct eco_ubus_request, req);
    struct ev_loop *loop = eco_req->ctx->ctx->loop;
    lua_State *L = eco_req->ctx->ctx->L;
    lua_State *co = eco_req->co;
    int narg = 0;

    ev_timer_stop(loop, &eco_req->tmr);

    lua_pushlightuserdata(L, eco_req);
    lua_pushnil(L);
    lua_rawset(L, LUA_REGISTRYINDEX);

    if (eco_req->has_data) {
        narg = 1;
    } else if (ret != UBUS_STATUS_OK) {
        narg = 2;
        lua_pushnil(co);
        lua_pushstring(co, ubus_strerror(ret));
    }

    eco_resume(L, co, narg);
}

static int eco_ubus_call(lua_State *L)
{
    struct eco_ubus_context *ctx = lua_touserdata(L, 1);
    struct ev_loop *loop = ctx->ctx->loop;
    const char *path = luaL_checkstring(L, 2);
    const char *func = luaL_checkstring(L, 3);
    struct eco_ubus_request *req;
    uint32_t id;
    int ret;

    if (ubus_lookup_id(ctx->u, path, &id)) {
        lua_pushnil(L);
        lua_pushliteral(L, "not found");
        return 2;
    }

    blob_buf_init(&ctx->buf, 0);
    lua_table_to_blob(L, 4, &ctx->buf, false);

    req = lua_newuserdata(L, sizeof(struct eco_ubus_request));
    req->has_data = false;
    req->ctx = ctx;
    req->co = L;

    ret = ubus_invoke_async(ctx->u, id, func, ctx->buf.head, &req->req);
    if (ret) {
        lua_pushnil(L);
        lua_pushstring(L, ubus_strerror(ret));
        return 2;
    }

    req->req.data_cb = eco_ubus_call_data_cb;
    req->req.complete_cb = eco_ubus_call_complete_cb;
    ubus_complete_request_async(ctx->u, &req->req);

    ev_timer_init(&req->tmr, eco_ubus_call_timer_cb, ctx->timeout, 0);
    ev_timer_start(loop, &req->tmr);

    lua_pushlightuserdata(L, req);
    lua_insert(L, -2);
    lua_rawset(L, LUA_REGISTRYINDEX);

    return lua_yield(L, 0);
}

static int eco_ubus_reply(lua_State *L)
{
    struct eco_ubus_context *ctx = lua_touserdata(L, 1);
    struct ubus_request_data *req;

    luaL_checktype(L, 3, LUA_TTABLE);
    blob_buf_init(&ctx->buf, 0);

    lua_table_to_blob(L, 3, &ctx->buf, false);

    req = lua_touserdata(L, 2);
    ubus_send_reply(ctx->u, req, ctx->buf.head);

    return 0;
}

static void eco_ubus_event_handler(struct ubus_context *ctx, struct ubus_event_handler *ev,
            const char *type, struct blob_attr *msg)
{
    struct eco_ubus_event *e = container_of(ev, struct eco_ubus_event, e);
    lua_State *L = e->L;

    lua_pushlightuserdata(L, &eco_ubus_event_key);
    lua_rawget(L, LUA_REGISTRYINDEX);
    lua_rawgeti(L, -1, e->r);
    lua_remove(L, -2);

    blob_to_lua_table(L, blob_data(msg), blob_len(msg), false);

    lua_call(L, 1, 0);
}

static int eco_ubus_listen(lua_State *L)
{
    struct eco_ubus_context *ctx = lua_touserdata(L, 1);

    luaL_checktype(L, 2, LUA_TTABLE);

    lua_pushnil(L);

    while (lua_next(L, -2)) {
        struct eco_ubus_event *ev;

        /* check if the key is a string and the value is a method */
        if ((lua_type(L, -2) == LUA_TSTRING) && (lua_type(L, -1) == LUA_TFUNCTION)) {
            ev = calloc(1, sizeof(struct eco_ubus_event));
            ev->e.cb = eco_ubus_event_handler;
            ev->L = L;

            lua_pushlightuserdata(L, &eco_ubus_event_key);
            lua_rawget(L, LUA_REGISTRYINDEX);
            lua_pushvalue(L, -2);
            ev->r = luaL_ref(L, -2);
            lua_pop(L, 1);

            ubus_register_event_handler(ctx->u, &ev->e, lua_tostring(L, -2));
        }
        lua_pop(L, 1);
    }

    return 0;
}

static int eco_ubus_send(lua_State *L)
{
    struct eco_ubus_context *ctx = lua_touserdata(L, 1);
	const char *event = luaL_checkstring(L, 2);

	if (event[0] == '\0')
		return luaL_argerror(L, 2, "no event name");

	luaL_checktype(L, 3, LUA_TTABLE);
	blob_buf_init(&ctx->buf, 0);

    lua_table_to_blob(L, 3, &ctx->buf, false);

	ubus_send_event(ctx->u, event, ctx->buf.head);

	return 0;
}

static int eco_ubus_method_handler(struct ubus_context *ctx, struct ubus_object *obj,
		struct ubus_request_data *req, const char *method,
		struct blob_attr *msg)
{
    struct eco_ubus_object *o = container_of(obj, struct eco_ubus_object, o);
    lua_State *L = o->L;
    int rv = 0;

    lua_pushlightuserdata(L, &eco_ubus_method_key);
    lua_rawget(L, LUA_REGISTRYINDEX);
    lua_rawgeti(L, -1, o->r);
    lua_getfield(L, -1, method);
	lua_remove(L, -2);
	lua_remove(L, -2);

    lua_pushlightuserdata(L, req);

    if (!msg)
        lua_pushnil(L);
    else
        blob_to_lua_table(L, blob_data(msg), blob_len(msg), false);

    lua_call(L, 2, 1);

    if (lua_isnumber(L, -1))
		rv = lua_tonumber(L, -1);

    lua_pop(L, 1);

	return rv;
}

static int eco_ubus_load_methods(lua_State *L, struct ubus_method *m)
{
    struct blobmsg_policy *p;
    int plen;
    int pidx = 0;

    /* get the function pointer */
    lua_pushinteger(L, 1);
    lua_gettable(L, -2);

    /* get the policy table */
    lua_pushinteger(L, 2);
    lua_gettable(L, -3);

    /* check if the method table is valid */
    if ((lua_type(L, -2) != LUA_TFUNCTION) ||
            (lua_type(L, -1) != LUA_TTABLE) ||
            lua_rawlen(L, -1)) {
        lua_pop(L, 2);
        return 1;
    }

    /* store function pointer */
    lua_pushvalue(L, -2);
    lua_setfield(L, -6, lua_tostring(L, -5));

    m->name = lua_tostring(L, -4);
    m->handler = eco_ubus_method_handler;

    plen = lua_gettablelen(L, -1);

    /* exit if policy table is empty */
    if (!plen) {
        lua_pop(L, 2);
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
    lua_pop(L, 2);

    return 0;
}

static struct ubus_object *eco_ubus_load_object(lua_State *L)
{
    int mlen = lua_gettablelen(L, -1);
    struct eco_ubus_object *obj;
    struct ubus_method *m;
    int midx = 0;

    /* setup object pointers */
    obj = calloc(1, sizeof(struct eco_ubus_object));
    if (!obj)
        return NULL;

    obj->L = L;

    obj->o.name = lua_tostring(L, -2);

    /* setup method pointers */
    m = calloc(mlen, sizeof(struct ubus_method));
    obj->o.methods = m;

    /* setup type pointers */
    obj->o.type = calloc(1, sizeof(struct ubus_object_type));
    if (!obj->o.type) {
        free(m);
        free(obj);
        return NULL;
    }

    obj->o.type->name = lua_tostring(L, -2);
    obj->o.type->id = 0;
    obj->o.type->methods = obj->o.methods;

    /* create the callback lookup table */
    lua_createtable(L, 1, 0);
    lua_pushlightuserdata(L, &eco_ubus_method_key);
    lua_rawget(L, LUA_REGISTRYINDEX);
    lua_pushvalue(L, -2);
    obj->r = luaL_ref(L, -2);
    lua_pop(L, 1);

    /* scan each method */
    lua_pushnil(L);

    while (lua_next(L, -3) != 0) {
        /* check if it looks like a method */
        if ((lua_type(L, -2) != LUA_TSTRING) ||
                (lua_type(L, -1) != LUA_TTABLE) ||
                !lua_rawlen(L, -1)) {
            lua_pop(L, 1);
            continue;
        }

        if (!eco_ubus_load_methods(L, &m[midx]))
            midx++;
        lua_pop(L, 1);
    }

    obj->o.type->n_methods = obj->o.n_methods = midx;

    /* pop the callback table */
    lua_pop(L, 1);

    return &obj->o;
}

static int eco_ubus_add(lua_State *L)
{
    struct eco_ubus_context *ctx = lua_touserdata(L, 1);

    luaL_checktype(L, 2, LUA_TTABLE);

    lua_pushnil(L);

    while (lua_next(L, -2) != 0) {
        struct ubus_object *obj;

        /* check if the object has a table of methods */
        if ((lua_type(L, -2) == LUA_TSTRING) && (lua_type(L, -1) == LUA_TTABLE)) {
            obj = eco_ubus_load_object(L);
            if (obj)
                ubus_add_object(ctx->u, obj);
        }
        lua_pop(L, 1);
    }

    return 0;
}

static int eco_ubus_connect(lua_State *L)
{
    struct eco_context *ctx = eco_check_context(L);
    struct ev_loop *loop = ctx->loop;
    const char *sock = luaL_optstring(L, 1, NULL);
    double timeout = luaL_optnumber(L, 2, 30.0);
    struct eco_ubus_context *uc;
    struct ubus_context *u;

    u = ubus_connect(sock);
    if (!u) {
        lua_pushnil(L);
        lua_pushliteral(L, "Failed to connect to ubus");
        return 2;
    }

    uc = lua_newuserdata(L, sizeof(struct eco_ubus_context));
    lua_pushvalue(L, lua_upvalueindex(1));
    lua_setmetatable(L, -2);

    memset(uc, 0, sizeof(struct eco_ubus_context));

    ev_io_init(&uc->ior, eco_ubus_read_cb, u->sock.fd, EV_READ);
    ev_io_start(loop, &uc->ior);

    uc->ctx = ctx;
    uc->timeout = timeout;
    uc->u = u;

    return 1;
}

static const struct luaL_Reg ubus_metatable[] =  {
    {"call", eco_ubus_call},
    {"reply", eco_ubus_reply},
    {"listen", eco_ubus_listen},
    {"send", eco_ubus_send},
    {"add", eco_ubus_add},
    {"settimeout", eco_ubus_settimeout},
    {"signatures", eco_ubus_signatures},
    {"objects", eco_ubus_objects},
    {"close", eco_ubus_close},
    {"__gc", eco_ubus_gc},
    {NULL, NULL}
};

int luaopen_eco_ubus(lua_State *L)
{
    lua_pushlightuserdata(L, &eco_ubus_event_key);
    lua_newtable(L);
    lua_rawset(L, LUA_REGISTRYINDEX);

    lua_pushlightuserdata(L, &eco_ubus_method_key);
    lua_newtable(L);
    lua_rawset(L, LUA_REGISTRYINDEX);

    lua_newtable(L);

    lua_add_constant("ARRAY", BLOBMSG_TYPE_ARRAY);
    lua_add_constant("TABLE", BLOBMSG_TYPE_TABLE);
    lua_add_constant("STRING", BLOBMSG_TYPE_STRING);
    lua_add_constant("INT64", BLOBMSG_TYPE_INT64);
    lua_add_constant("INT32", BLOBMSG_TYPE_INT32);
    lua_add_constant("INT16", BLOBMSG_TYPE_INT16);
    lua_add_constant("INT8", BLOBMSG_TYPE_INT8);
    lua_add_constant("DOUBLE", BLOBMSG_TYPE_DOUBLE);
    lua_add_constant("BOOLEAN", BLOBMSG_TYPE_BOOL);

    eco_new_metatable(L, ubus_metatable);
    lua_pushcclosure(L, eco_ubus_connect, 1);
    lua_setfield(L, -2, "connect");

    return 1;
}
