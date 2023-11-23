/* SPDX-License-Identifier: MIT */
/*
 * Author: Jianhui Zhao <zhaojh329@gmail.com>
 */

#include <libssh2.h>

#include "eco.h"

#define ECO_SSH_SESSION_MT "eco{ssh.session}"
#define ECO_SSH_CHANNEL_MT "eco{ssh.channel}"

struct eco_ssh_session {
    LIBSSH2_SESSION *session;
};

struct eco_ssh_channel {
    LIBSSH2_SESSION *session;
    LIBSSH2_CHANNEL *channel;
};

static int lua_ssh_session_new(lua_State *L)
{
    struct eco_ssh_session *session = lua_newuserdata(L, sizeof(struct eco_ssh_session));

    lua_pushvalue(L, lua_upvalueindex(1));
    lua_setmetatable(L, -2);

    libssh2_init(0);

    session->session = libssh2_session_init();

    libssh2_session_set_blocking(session->session, 0);

    return 1;
}

static int lua_ssh_session_block_directions(lua_State *L)
{
    struct eco_ssh_session *session = luaL_checkudata(L, 1, ECO_SSH_SESSION_MT);
    int dir;

    if (!session->session)
        return luaL_error(L, "session freed");

    dir = libssh2_session_block_directions(session->session);

    lua_pushinteger(L, dir);

    return 1;
}

/* In case of success, it returns true, in case of error，it returns nil with an error code */
static int lua_ssh_session_handshake(lua_State *L)
{
    struct eco_ssh_session *session = luaL_checkudata(L, 1, ECO_SSH_SESSION_MT);
    int sock = luaL_checkinteger(L, 2);
    int rc;

    if (!session->session)
        return luaL_error(L, "session freed");

    rc = libssh2_session_handshake(session->session, sock);
    if (rc) {
        lua_pushnil(L);
        lua_pushinteger(L, rc);
        return 2;
    }

    lua_pushboolean(L, true);

    return 1;
}

static int lua_ssh_session_userauth_list(lua_State *L)
{
    struct eco_ssh_session *session = luaL_checkudata(L, 1, ECO_SSH_SESSION_MT);
    const char *username = luaL_checkstring(L, 2);
    char *userauthlist;

    if (!session->session)
        return luaL_error(L, "session freed");

    userauthlist = libssh2_userauth_list(session->session, username, strlen(username));
    if (!userauthlist) {
        char *err_msg;

        libssh2_session_last_error(session->session, &err_msg, NULL, 0);
        lua_pushnil(L);
        lua_pushstring(L, err_msg);

        return 2;
    }

    lua_pushstring(L, userauthlist);
    return 1;
}

/* In case of success, it returns true, in case of error，it returns nil with an error code */
static int lua_ssh_session_userauth_password(lua_State *L)
{
    struct eco_ssh_session *session = luaL_checkudata(L, 1, ECO_SSH_SESSION_MT);
    const char *username = luaL_checkstring(L, 2);
    const char *password = luaL_checkstring(L, 3);
    int rc;

    if (!session->session)
        return luaL_error(L, "session freed");

    rc = libssh2_userauth_password(session->session, username, password);
    if (rc) {
        lua_pushnil(L);
        lua_pushinteger(L, rc);
        return 2;
    }

    lua_pushboolean(L, true);

    return 1;
}

/* In case of success, it returns true, in case of error，it returns nil with an error code */
static int lua_ssh_channel_exec(lua_State *L)
{
    struct eco_ssh_channel *channel = luaL_checkudata(L, 1, ECO_SSH_CHANNEL_MT);
    const char *cmd = luaL_checkstring(L, 2);
    int rc;

    if (!channel->channel)
        return luaL_error(L, "channel freed");

    rc = libssh2_channel_exec(channel->channel, cmd);
    if (rc) {
        lua_pushnil(L);
        lua_pushinteger(L, rc);
        return 2;
    }

    lua_pushboolean(L, true);

    return 1;
}

/* In case of success, it returns a string, in case of error，it returns nil with an error code */
static int lua_ssh_channel_read(lua_State *L)
{
    struct eco_ssh_channel *channel = luaL_checkudata(L, 1, ECO_SSH_CHANNEL_MT);
    int stream_id = luaL_checkinteger(L, 2);
    char buffer[4096];
    ssize_t nread;

    if (!channel->channel)
        return luaL_error(L, "channel freed");

    nread = libssh2_channel_read_ex(channel->channel, stream_id, buffer, sizeof(buffer));
    if (nread < 0) {
        lua_pushnil(L);
        lua_pushinteger(L, nread);
        return 2;
    }

    lua_pushlstring(L, buffer, nread);

    return 1;
}

/* In case of success, it returns a number indicates writen, in case of error，it returns nil with an error code */
static int lua_ssh_channel_write(lua_State *L)
{
    struct eco_ssh_channel *channel = luaL_checkudata(L, 1, ECO_SSH_CHANNEL_MT);
    size_t len;
    const char *data = luaL_checklstring(L, 2, &len);
    ssize_t nwritten;

    if (!channel->channel)
        return luaL_error(L, "channel freed");

    nwritten = libssh2_channel_write(channel->channel, data, len);
    if (nwritten < 0) {
        lua_pushnil(L);
        lua_pushinteger(L, nwritten);
        return 2;
    }

    lua_pushinteger(L, nwritten);

    return 1;
}

/* In case of success, it returns true, in case of error，it returns nil with an error code */
static int lua_ssh_channel_send_eof(lua_State *L)
{
    struct eco_ssh_channel *channel = luaL_checkudata(L, 1, ECO_SSH_CHANNEL_MT);
    int rc;

    if (!channel->channel)
        return luaL_error(L, "channel freed");

    rc = libssh2_channel_send_eof(channel->channel);
    if (rc) {
        lua_pushnil(L);
        lua_pushinteger(L, rc);
        return 2;
    }

    lua_pushboolean(L, true);

    return 1;
}

/* In case of success, it returns true, in case of error，it returns nil with an error code */
static int lua_ssh_channel_wait_eof(lua_State *L)
{
    struct eco_ssh_channel *channel = luaL_checkudata(L, 1, ECO_SSH_CHANNEL_MT);
    int rc;

    if (!channel->channel)
        return luaL_error(L, "channel freed");

    rc = libssh2_channel_wait_eof(channel->channel);
    if (rc) {
        lua_pushnil(L);
        lua_pushinteger(L, rc);
        return 2;
    }

    lua_pushboolean(L, true);

    return 1;
}

/* In case of success, it returns true, in case of error，it returns nil with an error code */
static int lua_ssh_channel_wait_closed(lua_State *L)
{
    struct eco_ssh_channel *channel = luaL_checkudata(L, 1, ECO_SSH_CHANNEL_MT);
    int rc;

    if (!channel->channel)
        return luaL_error(L, "channel freed");

    rc = libssh2_channel_wait_closed(channel->channel);
    if (rc) {
        lua_pushnil(L);
        lua_pushinteger(L, rc);
        return 2;
    }

    lua_pushboolean(L, true);

    return 1;
}

/* In case of success, it returns true, in case of error，it returns nil with an error code */
static int lua_ssh_channel_close(lua_State *L)
{
    struct eco_ssh_channel *channel = luaL_checkudata(L, 1, ECO_SSH_CHANNEL_MT);
    int rc;

    if (!channel->channel)
        return luaL_error(L, "channel freed");

    rc = libssh2_channel_close(channel->channel);
    if (rc) {
        lua_pushnil(L);
        lua_pushinteger(L, rc);
        return 2;
    }

    lua_pushboolean(L, true);

    return 1;
}

static int lua_ssh_channel_get_exit_status(lua_State *L)
{
    struct eco_ssh_channel *channel = luaL_checkudata(L, 1, ECO_SSH_CHANNEL_MT);
    int exitcode;

    if (!channel->channel)
        return luaL_error(L, "channel freed");

    exitcode = libssh2_channel_get_exit_status(channel->channel);

    lua_pushinteger(L, exitcode);

    return 1;
}

static int lua_ssh_channel_get_exit_signal(lua_State *L)
{
    struct eco_ssh_channel *channel = luaL_checkudata(L, 1, ECO_SSH_CHANNEL_MT);
    char *exitsignal;

    if (!channel->channel)
        return luaL_error(L, "channel freed");

    libssh2_channel_get_exit_signal(channel->channel, &exitsignal, NULL, NULL, NULL, NULL, NULL);

    if (exitsignal)
        lua_pushstring(L, exitsignal);
    else
        lua_pushnil(L);

    return 1;
}

/* In case of success, it returns true, in case of error，it returns nil with an error code */
static int lua_ssh_channel_signal(lua_State *L)
{
    struct eco_ssh_channel *channel = luaL_checkudata(L, 1, ECO_SSH_CHANNEL_MT);
    int rc = 0;

    if (!channel->channel)
        return luaL_error(L, "channel freed");

#ifdef libssh2_channel_signal
    rc = libssh2_channel_signal(channel->channel, luaL_checkstring(L, 2));
#endif
    if (rc) {
        lua_pushnil(L);
        lua_pushinteger(L, rc);
        return 2;
    }

    lua_pushboolean(L, true);

    return 1;
}

/* In case of success, it returns true, in case of error，it returns nil with an error code */
static int lua_ssh_channel_free(lua_State *L)
{
    struct eco_ssh_channel *channel = luaL_checkudata(L, 1, ECO_SSH_CHANNEL_MT);
    int rc;

    if (!channel->channel)
        return 0;

    rc = libssh2_channel_free(channel->channel);
    if (rc) {
        lua_pushnil(L);
        lua_pushinteger(L, rc);
        return 2;
    }

    channel->channel = NULL;

    lua_pushboolean(L, true);

    return 1;
}

static const luaL_Reg channel_methods[] = {
    {"exec", lua_ssh_channel_exec},
    {"read", lua_ssh_channel_read},
    {"write", lua_ssh_channel_write},
    {"send_eof", lua_ssh_channel_send_eof},
    {"wait_eof", lua_ssh_channel_wait_eof},
    {"wait_closed", lua_ssh_channel_wait_closed},
    {"close", lua_ssh_channel_close},
    {"get_exit_status", lua_ssh_channel_get_exit_status},
    {"get_exit_signal", lua_ssh_channel_get_exit_signal},
    {"signal", lua_ssh_channel_signal},
    {"free", lua_ssh_channel_free},
    {NULL, NULL}
};

/* In case of success, it returns a userdata, in case of error，it returns nil with an error string */
static int lua_ssh_session_open_channel(lua_State *L)
{
    struct eco_ssh_session *session = luaL_checkudata(L, 1, ECO_SSH_SESSION_MT);
    struct eco_ssh_channel *lchannel;
    LIBSSH2_CHANNEL *channel;

    if (!session->session)
        return luaL_error(L, "session freed");

    channel = libssh2_channel_open_session(session->session);
    if (!channel) {
        char *err_msg;

        libssh2_session_last_error(session->session, &err_msg, NULL, 0);
        lua_pushnil(L);
        lua_pushstring(L, err_msg);

        return 2;
    }

    lchannel = lua_newuserdata(L, sizeof(struct eco_ssh_channel));
    eco_new_metatable(L, ECO_SSH_CHANNEL_MT, channel_methods);
    lua_setmetatable(L, -2);

    lchannel->session = session->session;
    lchannel->channel = channel;

    return 1;
}

/* In case of success, it returns a userdata, in case of error，it returns nil with an error string */
static int lua_ssh_session_scp_recv(lua_State *L)
{
    struct eco_ssh_session *session = luaL_checkudata(L, 1, ECO_SSH_SESSION_MT);
    const char *path = luaL_checkstring(L, 2);
    libssh2_struct_stat fileinfo;
    struct eco_ssh_channel *lchannel;
    LIBSSH2_CHANNEL *channel;

    if (!session->session)
        return luaL_error(L, "session freed");

    channel = libssh2_scp_recv2(session->session, path, &fileinfo);
    if (!channel) {
        char *err_msg;

        libssh2_session_last_error(session->session, &err_msg, NULL, 0);
        lua_pushnil(L);
        lua_pushstring(L, err_msg);

        return 2;
    }

    lchannel = lua_newuserdata(L, sizeof(struct eco_ssh_channel));
    eco_new_metatable(L, ECO_SSH_CHANNEL_MT, channel_methods);
    lua_setmetatable(L, -2);

    lchannel->session = session->session;
    lchannel->channel = channel;

    lua_pushinteger(L, fileinfo.st_size);

    return 2;
}

/* In case of success, it returns a userdata, in case of error，it returns nil with an error string */
static int lua_ssh_session_scp_send(lua_State *L)
{
    struct eco_ssh_session *session = luaL_checkudata(L, 1, ECO_SSH_SESSION_MT);
    const char *path = luaL_checkstring(L, 2);
    int mode = luaL_checkinteger(L, 3);
    size_t size = luaL_checkinteger(L, 4);
    struct eco_ssh_channel *lchannel;
    LIBSSH2_CHANNEL *channel;

    if (!session->session)
        return luaL_error(L, "session freed");

    channel = libssh2_scp_send(session->session, path, mode & 0777, size);
    if (!channel) {
        char *err_msg;

        libssh2_session_last_error(session->session, &err_msg, NULL, 0);
        lua_pushnil(L);
        lua_pushstring(L, err_msg);

        return 2;
    }

    lchannel = lua_newuserdata(L, sizeof(struct eco_ssh_channel));
    eco_new_metatable(L, ECO_SSH_CHANNEL_MT, channel_methods);
    lua_setmetatable(L, -2);

    lchannel->session = session->session;
    lchannel->channel = channel;

    return 1;
}

static int lua_ssh_session_last_error(lua_State *L)
{
    struct eco_ssh_session *session = luaL_checkudata(L, 1, ECO_SSH_SESSION_MT);
    char *err_msg = "";

    if (session->session)
        libssh2_session_last_error(session->session, &err_msg, NULL, 0);

    lua_pushstring(L, err_msg);

    return 1;
}

static int lua_ssh_session_last_errno(lua_State *L)
{
    struct eco_ssh_session *session = luaL_checkudata(L, 1, ECO_SSH_SESSION_MT);
    int err_code = 0;

    if (session->session)
        err_code = libssh2_session_last_errno(session->session);

    lua_pushinteger(L, err_code);

    return 1;
}

/* In case of success, it returns true, in case of error，it returns nil with an error code */
static int lua_ssh_session_disconnect(lua_State *L)
{
    struct eco_ssh_session *session = luaL_checkudata(L, 1, ECO_SSH_SESSION_MT);
    int reason = luaL_checkinteger(L, 2);
    const char *description = luaL_checkstring(L, 3);
    int rc;

    if (!session->session)
        goto done;

    rc = libssh2_session_disconnect_ex(session->session, reason, description, "");
    if (rc) {
        lua_pushnil(L);
        lua_pushinteger(L, rc);
        return 2;
    }

done:
    lua_pushboolean(L, true);
    return 1;
}

/* In case of success, it returns true, in case of error，it returns nil with an error code */
static int lua_ssh_session_free(lua_State *L)
{
    struct eco_ssh_session *session = luaL_checkudata(L, 1, ECO_SSH_SESSION_MT);
    int rc;

    if (!session->session)
        goto done;

    rc = libssh2_session_free(session->session);
    if (rc) {
        lua_pushnil(L);
        lua_pushinteger(L, rc);
        return 2;
    }

    session->session = NULL;

done:
    lua_pushboolean(L, true);
    return 1;
}

static const luaL_Reg session_methods[] = {
    {"block_directions", lua_ssh_session_block_directions},
    {"handshake", lua_ssh_session_handshake},
    {"userauth_list", lua_ssh_session_userauth_list},
    {"userauth_password", lua_ssh_session_userauth_password},
    {"open_channel", lua_ssh_session_open_channel},
    {"scp_recv", lua_ssh_session_scp_recv},
    {"scp_send", lua_ssh_session_scp_send},
    {"last_error", lua_ssh_session_last_error},
    {"last_errno", lua_ssh_session_last_errno},
    {"disconnect", lua_ssh_session_disconnect},
    {"free", lua_ssh_session_free},
    {NULL, NULL}
};

int luaopen_eco_core_ssh(lua_State *L)
{
    lua_newtable(L);

    lua_add_constant(L, "ERROR_NONE", LIBSSH2_ERROR_NONE);
    lua_add_constant(L, "ERROR_SOCKET_NONE", LIBSSH2_ERROR_SOCKET_NONE);
    lua_add_constant(L, "ERROR_BANNER_RECV", LIBSSH2_ERROR_BANNER_RECV);
    lua_add_constant(L, "ERROR_BANNER_SEND", LIBSSH2_ERROR_BANNER_SEND);
    lua_add_constant(L, "ERROR_INVALID_MAC", LIBSSH2_ERROR_INVALID_MAC);
    lua_add_constant(L, "ERROR_KEX_FAILURE", LIBSSH2_ERROR_KEX_FAILURE);
    lua_add_constant(L, "ERROR_ALLOC", LIBSSH2_ERROR_ALLOC);
    lua_add_constant(L, "ERROR_SOCKET_SEND", LIBSSH2_ERROR_SOCKET_SEND);
    lua_add_constant(L, "ERROR_KEY_EXCHANGE_FAILURE", LIBSSH2_ERROR_KEY_EXCHANGE_FAILURE);
    lua_add_constant(L, "ERROR_TIMEOUT", LIBSSH2_ERROR_TIMEOUT);
    lua_add_constant(L, "ERROR_HOSTKEY_INIT", LIBSSH2_ERROR_HOSTKEY_INIT);
    lua_add_constant(L, "ERROR_HOSTKEY_SIGN", LIBSSH2_ERROR_HOSTKEY_SIGN);
    lua_add_constant(L, "ERROR_DECRYPT", LIBSSH2_ERROR_DECRYPT);
    lua_add_constant(L, "ERROR_SOCKET_DISCONNECT", LIBSSH2_ERROR_SOCKET_DISCONNECT);
    lua_add_constant(L, "ERROR_PROTO", LIBSSH2_ERROR_PROTO);
    lua_add_constant(L, "ERROR_PASSWORD_EXPIRED", LIBSSH2_ERROR_PASSWORD_EXPIRED);
    lua_add_constant(L, "ERROR_FILE", LIBSSH2_ERROR_FILE);
    lua_add_constant(L, "ERROR_METHOD_NONE", LIBSSH2_ERROR_METHOD_NONE);
    lua_add_constant(L, "ERROR_AUTHENTICATION_FAILED", LIBSSH2_ERROR_AUTHENTICATION_FAILED);
    lua_add_constant(L, "ERROR_PUBLICKEY_UNRECOGNIZED", LIBSSH2_ERROR_PUBLICKEY_UNRECOGNIZED);
    lua_add_constant(L, "ERROR_PUBLICKEY_UNVERIFIED", LIBSSH2_ERROR_PUBLICKEY_UNVERIFIED);
    lua_add_constant(L, "ERROR_CHANNEL_OUTOFORDER", LIBSSH2_ERROR_CHANNEL_OUTOFORDER);
    lua_add_constant(L, "ERROR_CHANNEL_FAILURE", LIBSSH2_ERROR_CHANNEL_FAILURE);
    lua_add_constant(L, "ERROR_CHANNEL_REQUEST_DENIED", LIBSSH2_ERROR_CHANNEL_REQUEST_DENIED);
    lua_add_constant(L, "ERROR_CHANNEL_UNKNOWN", LIBSSH2_ERROR_CHANNEL_UNKNOWN);
    lua_add_constant(L, "ERROR_CHANNEL_WINDOW_EXCEEDED", LIBSSH2_ERROR_CHANNEL_WINDOW_EXCEEDED);
    lua_add_constant(L, "ERROR_CHANNEL_PACKET_EXCEEDED", LIBSSH2_ERROR_CHANNEL_PACKET_EXCEEDED);
    lua_add_constant(L, "ERROR_CHANNEL_CLOSED", LIBSSH2_ERROR_CHANNEL_CLOSED);
    lua_add_constant(L, "ERROR_CHANNEL_EOF_SENT", LIBSSH2_ERROR_CHANNEL_EOF_SENT);
    lua_add_constant(L, "ERROR_SCP_PROTOCOL", LIBSSH2_ERROR_SCP_PROTOCOL);
    lua_add_constant(L, "ERROR_ZLIB", LIBSSH2_ERROR_ZLIB);
    lua_add_constant(L, "ERROR_SOCKET_TIMEOUT", LIBSSH2_ERROR_SOCKET_TIMEOUT);
    lua_add_constant(L, "ERROR_SFTP_PROTOCOL", LIBSSH2_ERROR_SFTP_PROTOCOL);
    lua_add_constant(L, "ERROR_REQUEST_DENIED", LIBSSH2_ERROR_REQUEST_DENIED);
    lua_add_constant(L, "ERROR_METHOD_NOT_SUPPORTED", LIBSSH2_ERROR_METHOD_NOT_SUPPORTED);
    lua_add_constant(L, "ERROR_INVAL", LIBSSH2_ERROR_INVAL);
    lua_add_constant(L, "ERROR_INVALID_POLL_TYPE", LIBSSH2_ERROR_INVALID_POLL_TYPE);
    lua_add_constant(L, "ERROR_PUBLICKEY_PROTOCOL", LIBSSH2_ERROR_PUBLICKEY_PROTOCOL);
    lua_add_constant(L, "ERROR_EAGAIN", LIBSSH2_ERROR_EAGAIN);
    lua_add_constant(L, "ERROR_BUFFER_TOO_SMALL", LIBSSH2_ERROR_BUFFER_TOO_SMALL);
    lua_add_constant(L, "ERROR_BAD_USE", LIBSSH2_ERROR_BAD_USE);
    lua_add_constant(L, "ERROR_COMPRESS", LIBSSH2_ERROR_COMPRESS);
    lua_add_constant(L, "ERROR_OUT_OF_BOUNDARY", LIBSSH2_ERROR_OUT_OF_BOUNDARY);
    lua_add_constant(L, "ERROR_AGENT_PROTOCOL", LIBSSH2_ERROR_AGENT_PROTOCOL);
    lua_add_constant(L, "ERROR_SOCKET_RECV", LIBSSH2_ERROR_SOCKET_RECV);
    lua_add_constant(L, "ERROR_ENCRYPT", LIBSSH2_ERROR_ENCRYPT);
    lua_add_constant(L, "ERROR_BAD_SOCKET", LIBSSH2_ERROR_BAD_SOCKET);
    lua_add_constant(L, "ERROR_KNOWN_HOSTS", LIBSSH2_ERROR_KNOWN_HOSTS);
    lua_add_constant(L, "ERROR_CHANNEL_WINDOW_FULL", LIBSSH2_ERROR_CHANNEL_WINDOW_FULL);
    lua_add_constant(L, "ERROR_KEYFILE_AUTH_FAILED", LIBSSH2_ERROR_KEYFILE_AUTH_FAILED);
#ifdef LIBSSH2_ERROR_RANDGEN
    lua_add_constant(L, "ERROR_RANDGEN", LIBSSH2_ERROR_RANDGEN);
#endif
#ifdef LIBSSH2_ERROR_MISSING_USERAUTH_BANNER
    lua_add_constant(L, "ERROR_MISSING_USERAUTH_BANNER", LIBSSH2_ERROR_MISSING_USERAUTH_BANNER);
#endif
#ifdef LIBSSH2_ERROR_ALGO_UNSUPPORTED
    lua_add_constant(L, "ERROR_ALGO_UNSUPPORTED", LIBSSH2_ERROR_ALGO_UNSUPPORTED);
#endif

    lua_add_constant(L, "EXTENDED_DATA_STDERR", SSH_EXTENDED_DATA_STDERR);

    lua_add_constant(L, "SESSION_BLOCK_INBOUND", LIBSSH2_SESSION_BLOCK_INBOUND);
    lua_add_constant(L, "SESSION_BLOCK_OUTBOUND", LIBSSH2_SESSION_BLOCK_OUTBOUND);

    lua_add_constant(L, "DISCONNECT_HOST_NOT_ALLOWED_TO_CONNECT", SSH_DISCONNECT_HOST_NOT_ALLOWED_TO_CONNECT);
    lua_add_constant(L, "DISCONNECT_PROTOCOL_ERROR", SSH_DISCONNECT_PROTOCOL_ERROR);
    lua_add_constant(L, "DISCONNECT_KEY_EXCHANGE_FAILED", SSH_DISCONNECT_KEY_EXCHANGE_FAILED);
    lua_add_constant(L, "DISCONNECT_RESERVED", SSH_DISCONNECT_RESERVED);
    lua_add_constant(L, "DISCONNECT_MAC_ERROR", SSH_DISCONNECT_MAC_ERROR);
    lua_add_constant(L, "DISCONNECT_COMPRESSION_ERROR", SSH_DISCONNECT_COMPRESSION_ERROR);
    lua_add_constant(L, "DISCONNECT_SERVICE_NOT_AVAILABLE", SSH_DISCONNECT_SERVICE_NOT_AVAILABLE);
    lua_add_constant(L, "DISCONNECT_PROTOCOL_VERSION_NOT_SUPPORTED", SSH_DISCONNECT_PROTOCOL_VERSION_NOT_SUPPORTED);
    lua_add_constant(L, "DISCONNECT_HOST_KEY_NOT_VERIFIABLE", SSH_DISCONNECT_HOST_KEY_NOT_VERIFIABLE);
    lua_add_constant(L, "DISCONNECT_CONNECTION_LOST", SSH_DISCONNECT_CONNECTION_LOST);
    lua_add_constant(L, "DISCONNECT_BY_APPLICATION", SSH_DISCONNECT_BY_APPLICATION);
    lua_add_constant(L, "DISCONNECT_TOO_MANY_CONNECTIONS", SSH_DISCONNECT_TOO_MANY_CONNECTIONS);
    lua_add_constant(L, "DISCONNECT_AUTH_CANCELLED_BY_USER", SSH_DISCONNECT_AUTH_CANCELLED_BY_USER);
    lua_add_constant(L, "DISCONNECT_NO_MORE_AUTH_METHODS_AVAILABLE", SSH_DISCONNECT_NO_MORE_AUTH_METHODS_AVAILABLE);
    lua_add_constant(L, "DISCONNECT_ILLEGAL_USER_NAME", SSH_DISCONNECT_ILLEGAL_USER_NAME);

    eco_new_metatable(L, ECO_SSH_SESSION_MT, session_methods);
    lua_pushcclosure(L, lua_ssh_session_new, 1);
    lua_setfield(L, -2, "new");

    return 1;
}
