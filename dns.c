/* SPDX-License-Identifier: MIT */
/*
 * Author: Jianhui Zhao <zhaojh329@gmail.com>
 */

#include <sys/random.h>
#include <arpa/inet.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <errno.h>

#include "eco.h"

#define TYPE_A      1
#define TYPE_NS     2
#define TYPE_CNAME  5
#define TYPE_SOA    6
#define TYPE_PTR    12
#define TYPE_MX     15
#define TYPE_TXT    16
#define TYPE_AAAA   28
#define TYPE_SRV    33
#define TYPE_SPF    99

#define SECTION_AN  1

static const char *resolver_errs[] = {
    NULL,
    "format error",
    "server failure",
    "name error",
    "not implemented",
    "refused",
};

static int push_error(lua_State *L, const char *err)
{
    lua_pushnil(L);
    lua_pushstring(L, err);
    return 2;
}

static void set_integer_field(lua_State *L, const char *k, lua_Integer v)
{
    lua_pushinteger(L, v);
    lua_setfield(L, -2, k);
}

static void set_string_field(lua_State *L, const char *k, const char *v)
{
    lua_pushstring(L, v);
    lua_setfield(L, -2, k);
}

static int parse_name(const uint8_t *data, size_t data_len, int *offset,
                      char *buf, int buf_len, bool wire) {
    int pos = *offset;
    int written = 0;
    int name_len = 1;
    int jumped = 0;
    int jump_count = 0;

    while (true) {
        uint8_t len;

        if (pos >= data_len)
            return -1;

        len = data[pos++];
        if (len == 0) {
            if (!wire && written > 0)
                written--;

            buf[written] = '\0';

            if (!jumped)
                *offset = pos;

            return wire ? written + 1 : written;
        }

        if ((len & 0xc0) == 0xc0) {
            int ptr;

            if (pos >= data_len)
                return -1;

            ptr = ((len & 0x3F) << 8) | data[pos];
            pos++;

            if (!jumped) {
                *offset = pos;
                jumped = 1;
            }
            pos = ptr;
            if (++jump_count > 256)
                return -1;
            continue;
        }

        name_len += len + 1;
        if (len > 63 || name_len > 255)
            return -1;

        if (written + (wire ? len : len * 4) + 1 >= buf_len)
            return -1;

        if (pos + len > data_len)
            return -1;

        if (wire)
            buf[written++] = len;

        for (int i = 0; i < len; i++) {
            uint8_t c = data[pos++];

            if (!wire && (c <= 0x20 || c >= 0x7f)) {
                snprintf(buf + written, buf_len - written, "\\%03u", (unsigned int)c);
                written += 4;
            } else {
                if (!wire && (c == '.' || c == '\\'))
                    buf[written++] = '\\';
                buf[written++] = c;
            }
        }

        if (!wire)
            buf[written++] = '.';
    }
}

static bool match_question(const uint8_t *data, size_t data_len, int *offset,
                           const uint8_t *question, size_t question_len)
{
    char name[255];
    int len = parse_name(data, data_len, offset, name, sizeof(name), true);

    if (len < 0 || len + 4 != question_len || *offset + 4 > data_len)
        return false;

    /* Wire format preserves label boundaries and embedded NUL bytes. */
    for (int i = 0; i < len; i++) {
        uint8_t a = name[i];
        uint8_t b = question[i];

        if (a >= 'A' && a <= 'Z')
            a += 'a' - 'A';
        if (b >= 'A' && b <= 'Z')
            b += 'a' - 'A';
        if (a != b)
            return false;
    }

    if (memcmp(data + *offset, question + len, 4))
        return false;

    *offset += 4;
    return true;
}

static int parse_rr(lua_State *L, const uint8_t *buf, size_t buf_len, int *offset)
{
    uint32_t type, class, ttl, rdlength;
    char name[1024];
    int rstart;

    if (parse_name(buf, buf_len, offset, name, sizeof(name), false) < 0)
        return push_error(L, "malformed name");

    if (*offset + 10 > buf_len)
        return push_error(L, "malformed resource record header");

    type  = (buf[*offset] << 8) | buf[*offset + 1];
    class = (buf[*offset + 2] << 8) | buf[*offset + 3];
    ttl   = ((uint32_t)buf[*offset + 4] << 24) | (buf[*offset + 5] << 16) |
            (buf[*offset + 6] << 8)  | buf[*offset + 7];
    rdlength = (buf[*offset + 8] << 8) | buf[*offset + 9];

    *offset += 10;
    rstart = *offset;

    if (*offset + rdlength > buf_len)
        return push_error(L, "malformed resource record data");

    lua_createtable(L, 0, 10);
    set_integer_field(L, "section", SECTION_AN);
    set_integer_field(L, "type", type);
    set_integer_field(L, "class", class);
    set_integer_field(L, "ttl", ttl);
    set_string_field(L, "name", name);

    if (type == TYPE_A || type == TYPE_AAAA) {
        char ip[INET6_ADDRSTRLEN];

        if (type == TYPE_A) {
            if (rdlength != 4)
                return push_error(L, "invalid A record length");
        } else {
            if (rdlength != 16)
                return push_error(L, "invalid AAAA record length");
        }

        if (!inet_ntop(type == TYPE_A ? AF_INET : AF_INET6, buf + *offset, ip, sizeof(ip)))
            return push_error(L, "invalid IP address");

        set_string_field(L, "address", ip);

    } else if (type == TYPE_CNAME) {
        char cname[1024];
        int p = *offset;

        if (parse_name(buf, buf_len, &p, cname, sizeof(cname), false) < 0)
            return push_error(L, "malformed cname");

        if ((uint32_t)(p - *offset) != rdlength)
            return push_error(L, "bad cname record length");

        set_string_field(L, "cname", cname);

    } else if (type == TYPE_MX) {
        char host[1024];
        uint16_t pref;
        int p;

        if (rdlength < 3)
            return push_error(L, "bad MX record value length");

        pref = (buf[*offset] << 8) | buf[*offset + 1];
        set_integer_field(L, "preference", pref);

        p = *offset + 2;

        if (parse_name(buf, buf_len, &p, host, sizeof(host), false) < 0)
            return push_error(L, "malformed mx exchange");

        if ((p - *offset) != rdlength)
            return push_error(L, "bad mx record length");

        set_string_field(L, "exchange", host);

    } else if (type == TYPE_SRV) {
        uint16_t priority, weight, port;
        char target[1024];
        int p;

        if (rdlength < 7)
            return push_error(L, "bad SRV record value length");

        priority = (buf[*offset] << 8) | buf[*offset + 1];
        weight = (buf[*offset + 2] << 8) | buf[*offset + 3];
        port = (buf[*offset + 4] << 8) | buf[*offset + 5];

        set_integer_field(L, "priority", priority);
        set_integer_field(L, "weight", weight);
        set_integer_field(L, "port", port);

        p = *offset + 6;

        if (parse_name(buf, buf_len, &p, target, sizeof(target), false) < 0)
            return push_error(L, "malformed srv target");

        if (p - *offset != rdlength)
            return push_error(L, "bad srv record length");

        set_string_field(L, "target", target);

    } else if (type == TYPE_NS) {
        char nsdname[1024];
        int p = *offset;

        if (parse_name(buf, buf_len, &p, nsdname, sizeof(nsdname), false) < 0)
            return push_error(L, "malformed nsdname");

        if (p - *offset != rdlength)
            return push_error(L, "bad nsdname record length");

        set_string_field(L, "nsdname", nsdname);

    } else if (type == TYPE_TXT || type == TYPE_SPF) {
        const char *key = (type == TYPE_TXT) ? "txt" : "spf";
        int p = *offset;
        int last = *offset + rdlength;
        int count = 0;

        lua_createtable(L, 4, 0);

        while (p < last) {
            uint8_t slen;

            slen = buf[p++];
            if (p + slen > last)
                return push_error(L, "malformed TXT/SPF string");

            lua_pushlstring(L, (const char *)(buf + p), slen);
            lua_rawseti(L, -2, ++count);
            p += slen;
        }

        if (count == 0) {
            return push_error(L, "bad TXT/SPF record length");
        } else if (count == 1) {
            lua_rawgeti(L, -1, 1);
            lua_setfield(L, -3, key);
            lua_pop(L, 1);
        } else {
            lua_setfield(L, -2, key);
        }

    } else if (type == TYPE_PTR) {
        char ptrdname[1024];
        int p = *offset;

        if (parse_name(buf, buf_len, &p, ptrdname, sizeof(ptrdname), false) < 0)
            return push_error(L, "malformed ptrdname");

        if ((p - *offset) != rdlength)
            return push_error(L, "bad ptrdname record length");

        set_string_field(L, "ptrdname", ptrdname);

    } else if (type == TYPE_SOA) {
        static const char *soa_fields[] = {
            "serial", "refresh", "retry", "expire", "minimum"
        };
        char mname[1024], rname[1024];
        int p = *offset;
        int i;

        if (parse_name(buf, buf_len, &p, mname, sizeof(mname), false) < 0)
            return push_error(L, "malformed soa mname");

        if (parse_name(buf, buf_len, &p, rname, sizeof(rname), false) < 0)
            return push_error(L, "malformed soa rname");

        set_string_field(L, "mname", mname);
        set_string_field(L, "rname", rname);

        if (p + 20 > *offset + (int)rdlength)
            return push_error(L, "bad SOA record value length");

        for (i = 0; i < 5; i++) {
            uint32_t v = ((uint32_t)buf[p] << 24) | (buf[p + 1] << 16) |
                         (buf[p + 2] << 8) | buf[p + 3];
            set_integer_field(L, soa_fields[i], v);
            p += 4;
        }

        if (p - *offset != rdlength)
            return push_error(L, "bad SOA record length");

    } else {
        lua_pushlstring(L, (const char *)(buf + *offset), rdlength);
        lua_setfield(L, -2, "rdata");
    }

    *offset = rstart + rdlength;

    return 0;
}

static int lua_parse_response(lua_State *L)
{
    size_t buf_len, req_len;
    const uint8_t *buf = (const uint8_t *)luaL_checklstring(L, 1, &buf_len);
    const uint8_t *req = (const uint8_t *)luaL_checklstring(L, 2, &req_len);
    int flags, code, qdcount, ancount;
    int offset = 12;

    luaL_argcheck(L, req_len >= 17, 2, "malformed request");

    /* No return values means an unrelated or unmatchable datagram. */
    if (buf_len < 12 || memcmp(buf, req, 2))
        return 0;

    flags   = (buf[2] << 8) | buf[3];
    qdcount = (buf[4] << 8) | buf[5];
    ancount = (buf[6] << 8) | buf[7];

    if ((flags & 0x8000) == 0 || (buf[2] & 0x78) != (req[2] & 0x78) ||
        qdcount != 1)
        return 0;

    if (!match_question(buf, buf_len, &offset, req + 12, req_len - 12))
        return 0;

    if ((flags & 0x0200) != 0)
        return push_error(L, "truncated");

    code = flags & 0x000f;

    if (code != 0) {
        const char *err = NULL;

        if (code < (sizeof(resolver_errs) / sizeof(resolver_errs[0])))
            err = resolver_errs[code];

        lua_pushnil(L);
        lua_pushfstring(L, err ? err : "unknown error code: %d", code);
        return 2;
    }

    lua_createtable(L, ancount, 0);

    for (int i = 0; i < ancount; i++) {
        if (parse_rr(L, buf, buf_len, &offset))
            return 2;
        lua_rawseti(L, -2, i + 1);
    }

    return 1;
}

static int lua_transaction_id(lua_State *L)
{
    uint16_t id;
    ssize_t n;

    do {
        n = getrandom(&id, sizeof(id), GRND_NONBLOCK);
    } while (n < 0 && errno == EINTR);

    if (n < 0)
        return push_errno(L, errno);

    if (n != sizeof(id))
        return push_error(L, "short random read");

    lua_pushinteger(L, id);
    return 1;
}

static const luaL_Reg funcs[] = {
    {"parse_response", lua_parse_response},
    {"transaction_id", lua_transaction_id},
    {NULL, NULL}
};

int luaopen_eco_internal_dns(lua_State *L)
{
    luaL_newlib(L, funcs);
    return 1;
}
