/* SPDX-License-Identifier: MIT */
/*
 * Author: Jianhui Zhao <zhaojh329@gmail.com>
 *
 * Referenced from https://github.com/flukso/lua-mosquitto/blob/master/lua-mosquitto.c
 */

#include <mosquitto.h>
#include <string.h>
#include <errno.h>

#include "eco.h"

enum connect_return_codes {
    CONN_ACCEPT,
    CONN_REF_BAD_PROTOCOL,
    CONN_REF_BAD_ID,
    CONN_REF_SERVER_NOAVAIL,
    CONN_REF_BAD_LOGIN,
    CONN_REF_NO_AUTH,
    CONN_REF_BAD_TLS
};

#define ECO_MQTT_CTX_MT	"eco.mqtt"

struct eco_mqtt_ctx {
    lua_State *L;
    struct mosquitto *mosq;
    int on_connect;
    int on_disconnect;
    int on_publish;
    int on_message;
    int on_subscribe;
    int on_unsubscribe;
    int on_log;
};

static int mosq__pstatus(lua_State *L, int mosq_errno)
{
    switch (mosq_errno) {
        case MOSQ_ERR_SUCCESS:
            lua_pushboolean(L, true);
            return 1;
            break;

        case MOSQ_ERR_INVAL:
        case MOSQ_ERR_NOMEM:
        case MOSQ_ERR_PROTOCOL:
        case MOSQ_ERR_NOT_SUPPORTED:
            return luaL_error(L, mosquitto_strerror(mosq_errno));
            break;

        case MOSQ_ERR_NO_CONN:
        case MOSQ_ERR_CONN_LOST:
        case MOSQ_ERR_PAYLOAD_SIZE:
            lua_pushnil(L);
            lua_pushinteger(L, mosq_errno);
            lua_pushstring(L, mosquitto_strerror(mosq_errno));
            return 3;
            break;

        case MOSQ_ERR_ERRNO:
            lua_pushnil(L);
            lua_pushinteger(L, errno);
            lua_pushstring(L, strerror(errno));
            return 3;
            break;
    }

    return 0;
}

static int mosq_version(lua_State *L)
{
    int major, minor, rev;

    mosquitto_lib_version(&major, &minor, &rev);
    lua_pushfstring(L, "%i.%i.%i", major, minor, rev);

    return 1;
}

static void ctx__on_init(struct eco_mqtt_ctx *ctx)
{
    ctx->on_connect = LUA_REFNIL;
    ctx->on_disconnect = LUA_REFNIL;
    ctx->on_publish = LUA_REFNIL;
    ctx->on_message = LUA_REFNIL;
    ctx->on_subscribe = LUA_REFNIL;
    ctx->on_unsubscribe = LUA_REFNIL;
    ctx->on_log = LUA_REFNIL;
}

static void ctx__on_clear(struct eco_mqtt_ctx *ctx)
{
    luaL_unref(ctx->L, LUA_REGISTRYINDEX, ctx->on_connect);
    luaL_unref(ctx->L, LUA_REGISTRYINDEX, ctx->on_disconnect);
    luaL_unref(ctx->L, LUA_REGISTRYINDEX, ctx->on_publish);
    luaL_unref(ctx->L, LUA_REGISTRYINDEX, ctx->on_message);
    luaL_unref(ctx->L, LUA_REGISTRYINDEX, ctx->on_subscribe);
    luaL_unref(ctx->L, LUA_REGISTRYINDEX, ctx->on_unsubscribe);
    luaL_unref(ctx->L, LUA_REGISTRYINDEX, ctx->on_log);
}

static int mosq_new(lua_State *L)
{
    struct eco_context *eco = luaL_checkudata(L, 1, ECO_CTX_MT);
    const char *id = luaL_optstring(L, 2, NULL);
    bool clean_session = lua_isboolean(L, 3) ? lua_toboolean(L, 3) : true;
    struct eco_mqtt_ctx *ctx;

    if (!id && !clean_session)
        return luaL_argerror(L, 2, "if 'id' is nil then 'clean session' must be true");

    ctx = lua_newuserdata(L, sizeof(struct eco_mqtt_ctx));
    lua_pushvalue(L, lua_upvalueindex(1));
    lua_setmetatable(L, -2);

    /* ctx will be passed as void *obj arg in the callback functions */
    ctx->mosq = mosquitto_new(id, clean_session, ctx);

    if (!ctx->mosq)
        return luaL_error(L, strerror(errno));

    ctx->L = eco->L;
    ctx__on_init(ctx);

    return 1;
}

static int ctx_destroy(lua_State *L)
{
    struct eco_mqtt_ctx *ctx = luaL_checkudata(L, 1, ECO_MQTT_CTX_MT);

    mosquitto_destroy(ctx->mosq);

    ctx__on_clear(ctx);

    return mosq__pstatus(L, MOSQ_ERR_SUCCESS);
}

static int ctx_reinitialise(lua_State *L)
{
    struct eco_mqtt_ctx *ctx = luaL_checkudata(L, 1, ECO_MQTT_CTX_MT);
    const char *id = luaL_optstring(L, 1, NULL);
    bool clean_session = (lua_isboolean(L, 2) ? lua_toboolean(L, 2) : true);
    int rc;

    if (!id && !clean_session)
        return luaL_argerror(L, 3, "if 'id' is nil then 'clean session' must be true");

    rc = mosquitto_reinitialise(ctx->mosq, id, clean_session, ctx);

    ctx__on_clear(ctx);
    ctx__on_init(ctx);

    return mosq__pstatus(L, rc);
}

static int ctx_will_set(lua_State *L)
{
    struct eco_mqtt_ctx *ctx = luaL_checkudata(L, 1, ECO_MQTT_CTX_MT);
    const char *topic = luaL_checkstring(L, 2);
    size_t payloadlen = 0;
    const void *payload = NULL;
    int qos, rc;
    bool retain;

    if (!lua_isnil(L, 3))
        payload = lua_tolstring(L, 3, &payloadlen);

    qos = luaL_optinteger(L, 4, 0);
    retain = lua_toboolean(L, 5);

    rc = mosquitto_will_set(ctx->mosq, topic, payloadlen, payload, qos, retain);
    return mosq__pstatus(L, rc);
}

static int ctx_will_clear(lua_State *L)
{
    struct eco_mqtt_ctx *ctx = luaL_checkudata(L, 1, ECO_MQTT_CTX_MT);

    int rc = mosquitto_will_clear(ctx->mosq);
    return mosq__pstatus(L, rc);
}

static int ctx_login_set(lua_State *L)
{
    struct eco_mqtt_ctx *ctx = luaL_checkudata(L, 1, ECO_MQTT_CTX_MT);
    const char *username = lua_isnil(L, 2) ? NULL : luaL_checkstring(L, 2);
    const char *password = lua_isnil(L, 3) ? NULL : luaL_checkstring(L, 3);
    int rc = mosquitto_username_pw_set(ctx->mosq, username, password);
    return mosq__pstatus(L, rc);
}

static int ctx_tls_set(lua_State *L)
{
    struct eco_mqtt_ctx *ctx = luaL_checkudata(L, 1, ECO_MQTT_CTX_MT);
    const char *cafile = luaL_optstring(L, 2, NULL);
    const char *capath = luaL_optstring(L, 3, NULL);
    const char *certfile = luaL_optstring(L, 4, NULL);
    const char *keyfile = luaL_optstring(L, 5, NULL);

    // the last param is a callback to a function that asks for a passphrase for a keyfile
    // our keyfiles should NOT have a passphrase
    int rc = mosquitto_tls_set(ctx->mosq, cafile, capath, certfile, keyfile, 0);
    return mosq__pstatus(L, rc);
}

static int ctx_tls_insecure_set(lua_State *L)
{
    struct eco_mqtt_ctx *ctx = luaL_checkudata(L, 1, ECO_MQTT_CTX_MT);
    bool value = lua_toboolean(L, 2);
    int rc = mosquitto_tls_insecure_set(ctx->mosq, value);
    return mosq__pstatus(L, rc);
}

static int ctx_tls_psk_set(lua_State *L)
{
    struct eco_mqtt_ctx *ctx = luaL_checkudata(L, 1, ECO_MQTT_CTX_MT);
    const char *psk = luaL_checkstring(L, 2);
    const char *identity = luaL_checkstring(L, 3);
    const char *ciphers = luaL_optstring(L, 4, NULL);
    int rc = mosquitto_tls_psk_set(ctx->mosq, psk, identity, ciphers);
    return mosq__pstatus(L, rc);
}

static int ctx_tls_opts_set(lua_State *L)
{
    struct eco_mqtt_ctx *ctx = luaL_checkudata(L, 1, ECO_MQTT_CTX_MT);
    const bool cert_required = lua_toboolean(L, 2);
    const char *tls_version = luaL_optstring(L, 3, NULL);
    const char *ciphers = luaL_optstring(L, 4, NULL);
    int rc = mosquitto_tls_opts_set(ctx->mosq, cert_required ? 1 : 0, tls_version, ciphers);
    return mosq__pstatus(L, rc);
}

static int ctx_option(lua_State *L)
{
    struct eco_mqtt_ctx *ctx = luaL_checkudata(L, 1, ECO_MQTT_CTX_MT);
    enum mosq_opt_t option = luaL_checkinteger(L, 2);
    int type = lua_type(L, 3);
    int rc;

    if (type == LUA_TNUMBER) {
        int val = lua_tonumber(L, 3);
        rc = mosquitto_int_option(ctx->mosq, option, val);
    } else if (type == LUA_TSTRING) {
        const char *val = lua_tolstring(L, 3, NULL);
        rc = mosquitto_string_option(ctx->mosq, option, val);
    } else {
        return luaL_argerror(L, 3, "values must be numeric or string");
    }
    return mosq__pstatus(L, rc);
}

static int ctx_connect(lua_State *L)
{
    struct eco_mqtt_ctx *ctx = luaL_checkudata(L, 1, ECO_MQTT_CTX_MT);
    const char *host = luaL_optstring(L, 2, "localhost");
    int port = luaL_optinteger(L, 3, 1883);
    int keepalive = luaL_optinteger(L, 4, 60);
    int rc =  mosquitto_connect(ctx->mosq, host, port, keepalive);
    return mosq__pstatus(L, rc);
}

static int ctx_disconnect(lua_State *L)
{
    struct eco_mqtt_ctx *ctx = luaL_checkudata(L, 1, ECO_MQTT_CTX_MT);
    int rc = mosquitto_disconnect(ctx->mosq);
    return mosq__pstatus(L, rc);
}

static int ctx_publish(lua_State *L)
{
    struct eco_mqtt_ctx *ctx = luaL_checkudata(L, 1, ECO_MQTT_CTX_MT);
    const char *topic = luaL_checkstring(L, 2);
    size_t payloadlen = 0;
    const void *payload = NULL;
    int mid;	/* message id is referenced in the publish callback */
    int qos, rc;
    bool retain;

    if (!lua_isnil(L, 3))
        payload = lua_tolstring(L, 3, &payloadlen);

    qos = luaL_optinteger(L, 4, 0);
    retain = lua_toboolean(L, 5);

    rc = mosquitto_publish(ctx->mosq, &mid, topic, payloadlen, payload, qos, retain);

    if (rc != MOSQ_ERR_SUCCESS)
        return mosq__pstatus(L, rc);

    lua_pushinteger(L, mid);
    return 1;
}

static int ctx_subscribe(lua_State *L)
{
    struct eco_mqtt_ctx *ctx = luaL_checkudata(L, 1, ECO_MQTT_CTX_MT);
    const char *sub = luaL_checkstring(L, 2);
    int qos = luaL_optinteger(L, 3, 0);
    int rc, mid;

    rc = mosquitto_subscribe(ctx->mosq, &mid, sub, qos);

    if (rc != MOSQ_ERR_SUCCESS)
        return mosq__pstatus(L, rc);

    lua_pushinteger(L, mid);
    return 1;
}

static int ctx_unsubscribe(lua_State *L)
{
    struct eco_mqtt_ctx *ctx = luaL_checkudata(L, 1, ECO_MQTT_CTX_MT);
    const char *sub = luaL_checkstring(L, 2);
    int rc, mid;

    rc = mosquitto_unsubscribe(ctx->mosq, &mid, sub);

    if (rc != MOSQ_ERR_SUCCESS) {
        return mosq__pstatus(L, rc);
    } else {
        lua_pushinteger(L, mid);
        return 1;
    }
}

static int ctx_socket(lua_State *L)
{
    struct eco_mqtt_ctx *ctx = luaL_checkudata(L, 1, ECO_MQTT_CTX_MT);
    int fd = mosquitto_socket(ctx->mosq);

    lua_pushinteger(L, fd);
    return 1;
}

static int ctx_loop_read(lua_State *L)
{
    struct eco_mqtt_ctx *ctx = luaL_checkudata(L, 1, ECO_MQTT_CTX_MT);
    int max_packets = luaL_optinteger(L, 2, 1);
    int rc = mosquitto_loop_read(ctx->mosq, max_packets);
    return mosq__pstatus(L, rc);
}

static int ctx_loop_write(lua_State *L)
{
    struct eco_mqtt_ctx *ctx = luaL_checkudata(L, 1, ECO_MQTT_CTX_MT);
    int max_packets = luaL_optinteger(L, 2, 1);
    int rc = mosquitto_loop_write(ctx->mosq, max_packets);
    return mosq__pstatus(L, rc);
}

static int ctx_loop_misc(lua_State *L)
{
    struct eco_mqtt_ctx *ctx = luaL_checkudata(L, 1, ECO_MQTT_CTX_MT);
    int rc = mosquitto_loop_misc(ctx->mosq);
    return mosq__pstatus(L, rc);
}

static int ctx_want_write(lua_State *L)
{
    struct eco_mqtt_ctx *ctx = luaL_checkudata(L, 1, ECO_MQTT_CTX_MT);
    lua_pushboolean(L, mosquitto_want_write(ctx->mosq));
    return 1;
}

static void ctx_on_connect(struct mosquitto *mosq, void *obj, int rc)
{
    struct eco_mqtt_ctx *ctx = obj;
    bool success = false;
    char *str = "reserved for future use";

    switch(rc) {
        case CONN_ACCEPT:
            success = true;
            str = "connection accepted";
            break;

        case CONN_REF_BAD_PROTOCOL:
            str = "connection refused - incorrect protocol version";
            break;

        case CONN_REF_BAD_ID:
            str = "connection refused - invalid client identifier";
            break;

        case CONN_REF_SERVER_NOAVAIL:
            str = "connection refused - server unavailable";
            break;

        case CONN_REF_BAD_LOGIN:
            str = "connection refused - bad username or password";
            break;

        case CONN_REF_NO_AUTH:
            str = "connection refused - not authorised";
            break;

        case CONN_REF_BAD_TLS:
            str = "connection refused - TLS error";
            break;
    }

    lua_rawgeti(ctx->L, LUA_REGISTRYINDEX, ctx->on_connect);

    lua_pushboolean(ctx->L, success);
    lua_pushinteger(ctx->L, rc);
    lua_pushstring(ctx->L, str);

    lua_call(ctx->L, 3, 0);
}


static void ctx_on_disconnect(struct mosquitto *mosq, void *obj, int rc)
{
    struct eco_mqtt_ctx *ctx = obj;
    bool success = true;
    char *str = "client-initiated disconnect";

    if (rc) {
        success = false;
        str = "unexpected disconnect";
    }

    lua_rawgeti(ctx->L, LUA_REGISTRYINDEX, ctx->on_disconnect);

    lua_pushboolean(ctx->L, success);
    lua_pushinteger(ctx->L, rc);
    lua_pushstring(ctx->L, str);

    lua_call(ctx->L, 3, 0);
}

static void ctx_on_publish(struct mosquitto *mosq, void *obj, int mid)
{
    struct eco_mqtt_ctx *ctx = obj;

    lua_rawgeti(ctx->L, LUA_REGISTRYINDEX, ctx->on_publish);
    lua_pushinteger(ctx->L, mid);
    lua_call(ctx->L, 1, 0);
}

static void ctx_on_message(struct mosquitto *mosq, void *obj,
        const struct mosquitto_message *msg)
{
    struct eco_mqtt_ctx *ctx = obj;

    lua_rawgeti(ctx->L, LUA_REGISTRYINDEX, ctx->on_message);

    lua_pushinteger(ctx->L, msg->mid);
    lua_pushstring(ctx->L, msg->topic);
    lua_pushlstring(ctx->L, msg->payload, msg->payloadlen);
    lua_pushinteger(ctx->L, msg->qos);
    lua_pushboolean(ctx->L, msg->retain);

    lua_call(ctx->L, 5, 0);
}

static void ctx_on_subscribe(struct mosquitto *mosq, void *obj, int mid,
        int qos_count, const int *granted_qos)
{
    struct eco_mqtt_ctx *ctx = obj;
    int i;

    lua_rawgeti(ctx->L, LUA_REGISTRYINDEX, ctx->on_subscribe);
    lua_pushinteger(ctx->L, mid);

    for (i = 0; i < qos_count; i++)
        lua_pushinteger(ctx->L, granted_qos[i]);

    lua_call(ctx->L, qos_count + 1, 0);
}

static void ctx_on_unsubscribe(struct mosquitto *mosq, void *obj, int mid)
{
    struct eco_mqtt_ctx *ctx = obj;

    lua_rawgeti(ctx->L, LUA_REGISTRYINDEX, ctx->on_unsubscribe);
    lua_pushinteger(ctx->L, mid);
    lua_call(ctx->L, 1, 0);
}

static void ctx_on_log(struct mosquitto *mosq, void *obj, int level, const char *str)
{
    struct eco_mqtt_ctx *ctx = obj;

    lua_rawgeti(ctx->L, LUA_REGISTRYINDEX, ctx->on_log);

    lua_pushinteger(ctx->L, level);
    lua_pushstring(ctx->L, str);

    lua_call(ctx->L, 2, 0);
}

static int ctx_callback_set(lua_State *L)
{
    struct eco_mqtt_ctx *ctx = luaL_checkudata(L, 1, ECO_MQTT_CTX_MT);
    const char *type = luaL_checkstring(L, 2);

    if (!lua_isfunction(L, 3))
        return luaL_argerror(L, 3, "expecting a callback function");

    int ref = luaL_ref(L, LUA_REGISTRYINDEX);

    if (!strcmp(type, "ON_CONNECT")) {
        ctx->on_connect = ref;
        mosquitto_connect_callback_set(ctx->mosq, ctx_on_connect);
    } else if (!strcmp(type, "ON_DISCONNECT")) {
        ctx->on_disconnect = ref;
        mosquitto_disconnect_callback_set(ctx->mosq, ctx_on_disconnect);
    } else if (!strcmp(type, "ON_PUBLISH")) {
        ctx->on_publish = ref;
        mosquitto_publish_callback_set(ctx->mosq, ctx_on_publish);
    } else if (!strcmp(type, "ON_MESSAGE")) {
        ctx->on_message = ref;
        mosquitto_message_callback_set(ctx->mosq, ctx_on_message);
    } else if (!strcmp(type, "ON_SUBSCRIBE")) {
        ctx->on_subscribe = ref;
        mosquitto_subscribe_callback_set(ctx->mosq, ctx_on_subscribe);
    } else if (!strcmp(type, "ON_UNSUBSCRIBE")) {
        ctx->on_unsubscribe = ref;
        mosquitto_unsubscribe_callback_set(ctx->mosq, ctx_on_unsubscribe);
    } else if (!strcmp(type, "ON_LOG")) {
        ctx->on_log = ref;
        mosquitto_log_callback_set(ctx->mosq, ctx_on_log);
    } else {
        luaL_unref(L, LUA_REGISTRYINDEX, ref);
        luaL_argerror(L, 2, "not a proper callback type");
    }

    return mosq__pstatus(L, MOSQ_ERR_SUCCESS);
}

static const struct luaL_Reg methods[] = {
    {"destroy",			ctx_destroy},
    {"reinitialise",	ctx_reinitialise},
    {"will_set",		ctx_will_set},
    {"will_clear",		ctx_will_clear},
    {"login_set",		ctx_login_set},
    {"tls_insecure_set",	ctx_tls_insecure_set},
    {"tls_set",		ctx_tls_set},
    {"tls_psk_set",		ctx_tls_psk_set},
    {"tls_opts_set",	ctx_tls_opts_set},
    {"option",		ctx_option},
    {"connect",			ctx_connect},
    {"disconnect",		ctx_disconnect},
    {"publish",			ctx_publish},
    {"subscribe",		ctx_subscribe},
    {"unsubscribe",		ctx_unsubscribe},
    {"socket",			ctx_socket},
    {"loop_read",			ctx_loop_read},
    {"loop_write",			ctx_loop_write},
    {"loop_misc",			ctx_loop_misc},
    {"want_write",		ctx_want_write},
    {"callback_set",	ctx_callback_set},
    {NULL,		NULL}
};

int luaopen_eco_core_mqtt(lua_State *L)
{
    lua_newtable(L);

    lua_pushcfunction(L, mosq_version);
    lua_setfield(L, -2, "mosq_version");

    eco_new_metatable(L, ECO_MQTT_CTX_MT, methods);
    lua_pushcclosure(L, mosq_new, 1);
    lua_setfield(L, -2, "new");

    lua_add_constant(L, "LOG_NONE",	MOSQ_LOG_NONE);
    lua_add_constant(L, "LOG_INFO",	MOSQ_LOG_INFO);
    lua_add_constant(L, "LOG_NOTICE",	MOSQ_LOG_NOTICE);
    lua_add_constant(L, "LOG_WARNING",	MOSQ_LOG_WARNING);
    lua_add_constant(L, "LOG_ERROR",	MOSQ_LOG_ERR);
    lua_add_constant(L, "LOG_DEBUG",	MOSQ_LOG_DEBUG);
    lua_add_constant(L, "LOG_ALL",		MOSQ_LOG_ALL);

    lua_add_constant(L, "OPT_PROTOCOL_VERSION",MOSQ_OPT_PROTOCOL_VERSION);
    lua_add_constant(L, "OPT_SSL_CTX",		MOSQ_OPT_SSL_CTX);
    lua_add_constant(L, "OPT_SSL_CTX_WITH_DEFAULTS", MOSQ_OPT_SSL_CTX_WITH_DEFAULTS);
    lua_add_constant(L, "OPT_RECEIVE_MAXIMUM",	MOSQ_OPT_RECEIVE_MAXIMUM);
    lua_add_constant(L, "OPT_SEND_MAXIMUM",	MOSQ_OPT_SEND_MAXIMUM);
    lua_add_constant(L, "OPT_TLS_KEYFORM",	MOSQ_OPT_TLS_KEYFORM);
    lua_add_constant(L, "OPT_TLS_ENGINE",	MOSQ_OPT_TLS_ENGINE);
    lua_add_constant(L, "OPT_TLS_ENGINE_KPASS_SHA1", MOSQ_OPT_TLS_ENGINE_KPASS_SHA1);
    lua_add_constant(L, "OPT_TLS_OCSP_REQUIRED", MOSQ_OPT_TLS_OCSP_REQUIRED);
    lua_add_constant(L, "OPT_TLS_ALPN",	MOSQ_OPT_TLS_ALPN);

    lua_add_constant(L, "PROTOCOL_V31",	MQTT_PROTOCOL_V31);
    lua_add_constant(L, "PROTOCOL_V311",	MQTT_PROTOCOL_V311);
    lua_add_constant(L, "PROTOCOL_V5",	MQTT_PROTOCOL_V5);

    return 1;
}
