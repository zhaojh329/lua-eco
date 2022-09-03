/*
 * MIT License
 *
 * Copyright (c) 2022 Jianhui Zhao <zhaojh329@gmail.com>
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

#include <http_parser.h>

#include "eco.h"

struct lua_http_parser {
    http_parser parser;
    lua_State *L;
    int ref;
};

static char http_parser_cb_key;

static int lua_http_parse_url(lua_State *L)
{
    bool is_connect = lua_toboolean(L, 2);
    struct http_parser_url u = {};
    const char *buf;
    size_t len;

    buf = luaL_checklstring(L, 1, &len);

    if (http_parser_parse_url(buf, len, is_connect, &u)) {
        lua_pushnil(L);
        return 1;
    }

    lua_newtable(L);

    if (u.field_set & (1 << UF_SCHEMA)) {
        lua_pushlstring(L, buf + u.field_data[UF_SCHEMA].off, u.field_data[UF_SCHEMA].len);
        lua_setfield(L, -2, "schema");
    }

    if (u.field_set & (1 << UF_HOST)) {
        lua_pushlstring(L, buf + u.field_data[UF_HOST].off, u.field_data[UF_HOST].len);
        lua_setfield(L, -2, "host");
    }

    if (u.field_set & (1 << UF_PATH)) {
        lua_pushlstring(L, buf + u.field_data[UF_PATH].off, u.field_data[UF_PATH].len);
        lua_setfield(L, -2, "path");
    }

    if (u.field_set & (1 << UF_QUERY)) {
        lua_pushlstring(L, buf + u.field_data[UF_QUERY].off, u.field_data[UF_QUERY].len);
        lua_setfield(L, -2, "query");
    }

    if (u.field_set & (1 << UF_FRAGMENT)) {
        lua_pushlstring(L, buf + u.field_data[UF_FRAGMENT].off, u.field_data[UF_FRAGMENT].len);
        lua_setfield(L, -2, "fragment");
    }

    if (u.field_set & (1 << UF_USERINFO)) {
        lua_pushlstring(L, buf + u.field_data[UF_USERINFO].off, u.field_data[UF_USERINFO].len);
        lua_setfield(L, -2, "userinfo");
    }

    lua_pushinteger(L, u.port);
    lua_setfield(L, -2, "port");

    return 1;
}

#define LUA_HTTP_PARSER_CB_DEF(name)                \
static int name##_callback(http_parser *p)          \
{                                                   \
    struct lua_http_parser *parser = p->data;       \
    lua_State *L = parser->L;                       \
                                                    \
    lua_pushlightuserdata(L, &http_parser_cb_key); \
    lua_rawget(L, LUA_REGISTRYINDEX);   \
    lua_rawgeti(L, -1, parser->ref);    \
    lua_remove(L, -2);                  \
                                        \
    lua_getfield(L, -1, #name);         \
                                        \
    if (!lua_isfunction(L, -1)) {       \
        lua_pop(L, 1);                  \
        return 0;                       \
    }                                   \
                                        \
                                        \
    lua_call(L, 0, 1);                  \
                                        \
    return lua_tointeger(L, -1);        \
}

#define LUA_HTTP_PARSER_DATA_CB_DEF(name)                                   \
static int name##_callback(http_parser *p, const char *at, size_t length)   \
{                                                                           \
    struct lua_http_parser *parser = p->data;       \
    lua_State *L = parser->L;                       \
                                                    \
    lua_pushlightuserdata(L, &http_parser_cb_key); \
    lua_rawget(L, LUA_REGISTRYINDEX);   \
    lua_rawgeti(L, -1, parser->ref);    \
    lua_remove(L, -2);                  \
                                        \
    lua_getfield(L, -1, #name);         \
                                        \
    if (!lua_isfunction(L, -1)) {       \
        lua_pop(L, 1);                  \
        return 0;                       \
    }                                   \
                                        \
    lua_pushlstring(L, at, length);     \
                                        \
    lua_call(L, 1, 1);                  \
                                        \
    return lua_tointeger(L, -1);        \
}

LUA_HTTP_PARSER_CB_DEF(on_message_begin)
LUA_HTTP_PARSER_DATA_CB_DEF(on_url)
LUA_HTTP_PARSER_DATA_CB_DEF(on_status)
LUA_HTTP_PARSER_DATA_CB_DEF(on_header_field)
LUA_HTTP_PARSER_DATA_CB_DEF(on_header_value)
LUA_HTTP_PARSER_CB_DEF(on_headers_complete)
LUA_HTTP_PARSER_DATA_CB_DEF(on_body)
LUA_HTTP_PARSER_CB_DEF(on_message_complete)
LUA_HTTP_PARSER_CB_DEF(on_chunk_header)
LUA_HTTP_PARSER_CB_DEF(on_chunk_complete)

static http_parser_settings settings = {
    .on_message_begin = on_message_begin_callback,
    .on_url = on_url_callback,
    .on_status = on_status_callback,
    .on_header_field = on_header_field_callback,
    .on_header_value = on_header_value_callback,
    .on_headers_complete = on_headers_complete_callback,
    .on_body = on_body_callback,
    .on_message_complete = on_message_complete_callback,
    .on_chunk_header = on_chunk_header_callback,
    .on_chunk_complete = on_chunk_complete_callback
};

static int http_parse_new(lua_State *L, int type)
{
    struct lua_http_parser *parser;

    parser = lua_newuserdata(L, sizeof(struct lua_http_parser));
    memset(parser, 0, sizeof(struct lua_http_parser));

    lua_pushvalue(L, lua_upvalueindex(1));
    lua_setmetatable(L, -2);

    parser->parser.data = parser;

    lua_pushlightuserdata(L, &http_parser_cb_key);
    lua_rawget(L, LUA_REGISTRYINDEX);
    lua_pushvalue(L, 1);
    parser->ref = luaL_ref(L, -2);
    lua_pop(L, 1);

    http_parser_init(&parser->parser, type);

    return 1;
}

static int http_parse_new_request(lua_State *L)
{
    return http_parse_new(L, HTTP_REQUEST);
}

static int http_parse_new_response(lua_State *L)
{
    return http_parse_new(L, HTTP_RESPONSE);
}

static int lua_set_max_header_size(lua_State *L)
{
    int size = luaL_checkinteger(L, 2);

    http_parser_set_max_header_size(size);

    return 0;
}

static int lua_http_parser_execute(lua_State *L)
{
    struct lua_http_parser *parser = lua_touserdata(L, 1);
    size_t recved, nparsed;
    const char *buf;

    parser->L = L;

    buf = luaL_checklstring(L, 2, &recved);
    nparsed = http_parser_execute(&parser->parser, &settings, buf, recved);
    if (nparsed != recved) {
        lua_pushnil(L);
        lua_pushstring(L, http_errno_description(parser->parser.http_errno));
        return 2;
    }

    lua_pushnumber(L, nparsed);
    return 1;
}

static int lua_http_method_str(lua_State *L)
{
    struct lua_http_parser *parser = lua_touserdata(L, 1);

    lua_pushstring(L, http_method_str(parser->parser.method));

    return 1;
}

static int lua_http_status_code(lua_State *L)
{
    struct lua_http_parser *parser = lua_touserdata(L, 1);

    lua_pushinteger(L, parser->parser.status_code);

    return 1;
}

static int lua_http_version(lua_State *L)
{
    struct lua_http_parser *parser = lua_touserdata(L, 1);

    lua_pushinteger(L, parser->parser.http_major);
    lua_pushinteger(L, parser->parser.http_minor);

    return 2;
}

static int lua_http_is_upgrade(lua_State *L)
{
    struct lua_http_parser *parser = lua_touserdata(L, 1);

    lua_pushboolean(L, parser->parser.upgrade);

    return 1;
}

static int lua_http_content_length(lua_State *L)
{
    struct lua_http_parser *parser = lua_touserdata(L, 1);

    lua_pushnumber(L, parser->parser.content_length);

    return 1;
}

static int lua_http_body_is_final(lua_State *L)
{
    struct lua_http_parser *parser = lua_touserdata(L, 1);

    lua_pushboolean(L, http_body_is_final(&parser->parser));

    return 1;
}

static int lua_http_parser_reset(lua_State *L)
{
    struct lua_http_parser *parser = lua_touserdata(L, 1);

    http_parser_init(&parser->parser, parser->parser.type);

    return 0;
}

static const struct luaL_Reg http_parser_metatable[] =  {
    {"set_max_header_size", lua_set_max_header_size},
    {"execute", lua_http_parser_execute},
    {"http_method", lua_http_method_str},
    {"status_code", lua_http_status_code},
    {"http_version", lua_http_version},
    {"is_upgrade", lua_http_is_upgrade},
    {"content_length", lua_http_content_length},
    {"body_is_final", lua_http_body_is_final},
    {"reset", lua_http_parser_reset},
    {NULL, NULL}
};

int luaopen_eco_http_parser(lua_State *L)
{
    lua_pushlightuserdata(L, &http_parser_cb_key);
    lua_newtable(L);
    lua_rawset(L, LUA_REGISTRYINDEX);

    lua_newtable(L);

    lua_pushcfunction(L, lua_http_parse_url);
    lua_setfield(L, -2, "parse_url");

    eco_new_metatable(L, http_parser_metatable);
    lua_pushcclosure(L, http_parse_new_request, 1);
    lua_setfield(L, -2, "request");

    eco_new_metatable(L, http_parser_metatable);
    lua_pushcclosure(L, http_parse_new_response, 1);
    lua_setfield(L, -2, "response");

    return 1;
}
