/* SPDX-License-Identifier: MIT */
/*
 * Author: Jianhui Zhao <zhaojh329@gmail.com>
 */

/**
 * Shared-memory dictionary.
 *
 * This module uses `mmap(MAP_SHARED)` on files under `/dev/shm` to provide
 * cross-process shared memory semantics.
 *
 * @module eco.shared
 */

#define _GNU_SOURCE

#include <sys/mman.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <time.h>
#include <string.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <stddef.h>
#include <math.h>

#include "eco.h"

#define SHARED_MT "struct eco_shared_dict *"

#define SHARED_MAGIC 0x45434f2d534844u /* ECO-SHD */

enum {
    TYPE_BOOL,
    TYPE_NUM,
    TYPE_STR
};

struct item_value {
    uint8_t type;
    size_t len;
    union {
        uint8_t value[0];
        uint8_t boolean;
        lua_Number number;
        const char *s;
    };
};

struct item_hdr {
    unsigned type:2;
    unsigned dead:1;
    unsigned hash:29;
    uint32_t key_len;
    uint32_t val_len;
    int64_t expires_at;
    char key[0];
};

struct shm_hdr {
    uint64_t magic;
    size_t len;
    uint8_t base[0];
};

struct eco_shared_dict {
    struct shm_hdr *hdr;
    size_t map_size;
    char path[256];
    int fd;
    bool owner;
};

static inline int64_t now_ms()
{
    struct timespec ts = {};
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (int64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

static struct eco_shared_dict *check_dict(lua_State *L)
{
    return luaL_checkudata(L, 1, SHARED_MT);
}

static inline uint8_t *item_val_ptr(struct item_hdr *item)
{
    return (uint8_t *)item->key + item->key_len;
}

static inline size_t item_size(const struct item_hdr *item)
{
    return sizeof(struct item_hdr) + item->key_len + item->val_len;
}

static inline bool item_is_dead(const struct item_hdr *item)
{
    if (item->dead)
        return true;

    if (item->expires_at > 0)
        return now_ms() > item->expires_at;

    return false;
}

static inline uint32_t calc_key_hash(const char *key, size_t key_len)
{
    /* FNV-1a 32-bit, folded to 29 bits to fit item_hdr bitfield. */
    uint32_t h = 2166136261u;

    for (size_t i = 0; i < key_len; i++) {
        h ^= (uint8_t)key[i];
        h *= 16777619u;
    }

    h &= 0x1fffffff;

    /* Reserve 0 for legacy/no-hash records. */
    if (h == 0)
        h = 1;

    return h;
}

static bool item_match(const struct item_hdr *item, const char *key, size_t key_len,
                       uint32_t hash)
{
    if (item_is_dead(item))
        return false;

    if (item->key_len != key_len)
        return false;

    if (item->hash != hash)
        return false;

    return !memcmp(item->key, key, key_len);
}

static void dict_gc(struct eco_shared_dict *dict)
{
    struct shm_hdr *hdr = dict->hdr;
    size_t src = 0;
    size_t dst = 0;

    while (src < hdr->len) {
        struct item_hdr *item = (struct item_hdr *)(hdr->base + src);
        size_t len = item_size(item);

        if (!item_is_dead(item)) {
            if (dst != src)
                memmove(hdr->base + dst, item, len);

            dst += len;
        }

        src += len;
    }

    hdr->len = dst;
}

static struct item_hdr *find_item(struct eco_shared_dict *dict, const char *key, size_t key_len,
                                  uint32_t hash)
{
    struct shm_hdr *hdr = dict->hdr;
    size_t offset = 0;

    while (offset < hdr->len) {
        struct item_hdr *item = (struct item_hdr *)(hdr->base + offset);

        if (item_match(item, key, key_len, hash))
            return item;

        offset += item_size(item);
    }

    return NULL;
}

static bool dict_del(struct eco_shared_dict *dict, const char *key, size_t key_len,
                     uint32_t hash)
{
    struct item_hdr *item = find_item(dict, key, key_len, hash);

    if (item) {
        item->dead = 1;
        return true;
    }

    return false;
}

/**
 * Dictionary object created by @{shared.new} or opened by @{shared.get}.
 *
 * Keys are strings. Values can be booleans, numbers, or strings.
 * Expiration time is stored per key and measured in seconds in the Lua API.
 *
 * @type dict
 */

/**
 * Delete a key.
 *
 * @function dict:del
 * @tparam string key
 * @treturn boolean removed `true` if the key existed and was deleted.
 */
static int lua_dict_del(lua_State *L)
{
    struct eco_shared_dict *dict = check_dict(L);
    size_t key_len;
    const char *key = luaL_checklstring(L, 2, &key_len);
    uint32_t hash;
    bool found;

    if (flock(dict->fd, LOCK_EX))
        return push_errno(L, errno);

    hash = calc_key_hash(key, key_len);

    found = dict_del(dict, key, key_len, hash);

    lua_pushboolean(L, found);
    flock(dict->fd, LOCK_UN);
    return 1;
}

/**
 * Set key to value.
 *
 * When `exptime` is positive, the key expires after `exptime` seconds.
 * If `exptime` is `0` or negative, the key is stored without expiration.
 *
 * @function dict:set
 * @tparam string key
 * @tparam string|number|boolean value
 * @tparam[opt] number exptime Expiration in seconds.
 * @treturn boolean ok
 * @treturn[2] nil
 * @treturn[2] string err
 */
static int lua_dict_set(lua_State *L)
{
    struct eco_shared_dict *dict = check_dict(L);
    struct shm_hdr *hdr = dict->hdr;
    size_t key_len;
    const char *key = luaL_checklstring(L, 2, &key_len);
    struct item_value value = {};
    lua_Number exptime = 0;
    struct item_hdr *item;
    size_t item_len;
    uint32_t hash;

    luaL_argcheck(L, key_len > 0, 2, "invalid key");

    if (!lua_isnoneornil(L, 4)) {
        exptime = luaL_checknumber(L, 4);
        luaL_argcheck(L, isfinite(exptime), 4, "exptime must be finite");
    }

    switch (lua_type(L, 3)) {
    case LUA_TBOOLEAN:
        value.type = TYPE_BOOL;
        value.len = 1;
        value.boolean = lua_toboolean(L, 3);
        break;

    case LUA_TNUMBER:
        value.type = TYPE_NUM;
        value.len = sizeof(lua_Number);
        value.number = lua_tonumber(L, 3);
        break;

    case LUA_TSTRING:
        value.type = TYPE_STR;
        value.s = luaL_checklstring(L, 3, &value.len);
        break;

    default:
        lua_pushnil(L);
        lua_pushliteral(L, "bad value type (only string/number/boolean)");
        return 2;
    }

    if (flock(dict->fd, LOCK_EX))
        return push_errno(L, errno);

    item_len = sizeof(struct item_hdr) + key_len + value.len;

    if (hdr->len + item_len > dict->map_size - sizeof(struct shm_hdr)) {
        dict_gc(dict);

        if (hdr->len + item_len > dict->map_size - sizeof(struct shm_hdr)) {
            lua_pushnil(L);
            lua_pushliteral(L, "no memory");
            flock(dict->fd, LOCK_UN);
            return 2;
        }
    }

    hash = calc_key_hash(key, key_len);

    dict_del(dict, key, key_len, hash);

    item = (struct item_hdr *)(hdr->base + hdr->len);

    item->dead = 0;
    item->type = value.type;
    item->hash = hash;
    item->key_len = key_len;
    item->val_len = value.len;

    if (exptime > 0)
        item->expires_at = now_ms() + (int64_t)(exptime * 1000);
    else
        item->expires_at = 0;

    memcpy(item->key, key, key_len);

    if (value.type == TYPE_STR)
        memcpy(item_val_ptr(item), value.s, value.len);
    else
        memcpy(item_val_ptr(item), value.value, value.len);

    hdr->len += item_len;

    flock(dict->fd, LOCK_UN);

    lua_pushboolean(L, true);
    return 1;
}

/**
 * Get value by key.
 *
 * Returns value if present; otherwise returns `nil`.
 *
 * @function dict:get
 * @tparam string key
 * @treturn any value
 */
static int lua_dict_get(lua_State *L)
{
    struct eco_shared_dict *dict = check_dict(L);
    size_t key_len;
    const char *key = luaL_checklstring(L, 2, &key_len);
    struct item_hdr *item;
    uint32_t hash;

    if (flock(dict->fd, LOCK_SH))
        return push_errno(L, errno);

    hash = calc_key_hash(key, key_len);
    item = find_item(dict, key, key_len, hash);
    if (!item) {
        flock(dict->fd, LOCK_UN);
        return 0;
    }

    switch (item->type) {
    case TYPE_BOOL:
        lua_pushboolean(L, *item_val_ptr(item));
        break;

    case TYPE_NUM: {
        lua_Number n;

        memcpy(&n, item_val_ptr(item), sizeof(n));
        lua_pushnumber(L, n);
        break;
    }

    case TYPE_STR:
        lua_pushlstring(L, (char *)item_val_ptr(item), item->val_len);
        break;

    default:
        lua_pushnil(L);
        break;
    }

    flock(dict->fd, LOCK_UN);
    return 1;
}

/**
 * Increment numeric value.
 *
 * The key must already exist and hold a number.
 * If `exptime` is provided, it replaces the key TTL.
 * If `exptime` is omitted, the previous TTL is preserved.
 *
 * @function dict:incr
 * @tparam string key
 * @tparam number value Delta.
 * @tparam[opt] number exptime Expiration in seconds.
 * @treturn number new_value
 * @treturn[2] nil
 * @treturn[2] string err
 */
static int lua_dict_incr(lua_State *L)
{
    struct eco_shared_dict *dict = check_dict(L);
    size_t key_len;
    const char *key = luaL_checklstring(L, 2, &key_len);
    lua_Number delta = luaL_checknumber(L, 3);
    lua_Number exptime = 0;
    bool has_exptime = false;
    struct item_hdr *item;
    uint32_t hash;
    lua_Number n;

    luaL_argcheck(L, isfinite(delta), 3, "delta must be finite");

    if (!lua_isnoneornil(L, 4)) {
        exptime = luaL_checknumber(L, 4);
        luaL_argcheck(L, isfinite(exptime), 4, "exptime must be finite");
        has_exptime = true;
    }

    if (flock(dict->fd, LOCK_EX))
        return push_errno(L, errno);

    hash = calc_key_hash(key, key_len);

    item = find_item(dict, key, key_len, hash);
    if (!item) {
        flock(dict->fd, LOCK_UN);
        return 0;
    }

    if (item->type != TYPE_NUM) {
        flock(dict->fd, LOCK_UN);
        lua_pushnil(L);
        lua_pushliteral(L, "not a number");
        return 2;
    }

    if (item->val_len != sizeof(lua_Number)) {
        flock(dict->fd, LOCK_UN);
        lua_pushnil(L);
        lua_pushliteral(L, "corrupted number value");
        return 2;
    }

    memcpy(&n, item_val_ptr(item), sizeof(n));
    n += delta;
    memcpy(item_val_ptr(item), &n, sizeof(n));

    if (has_exptime) {
        if (exptime > 0)
            item->expires_at = now_ms() + (int64_t)(exptime * 1000);
        else
            item->expires_at = 0;
    }

    flock(dict->fd, LOCK_UN);

    lua_pushnumber(L, n);
    return 1;
}

/**
 * Get remaining TTL in seconds.
 *
 * Returns `nil` if the key does not exist.
 * Returns `0` when the key exists but has no expiration.
 *
 * @function dict:ttl
 * @tparam string key
 * @treturn number|nil ttl
 */
static int lua_dict_ttl(lua_State *L)
{
    struct eco_shared_dict *dict = check_dict(L);
    size_t key_len;
    const char *key = luaL_checklstring(L, 2, &key_len);
    struct item_hdr *item;
    lua_Number exptime;
    uint32_t hash;

    if (flock(dict->fd, LOCK_SH))
        return push_errno(L, errno);

    hash = calc_key_hash(key, key_len);

    item = find_item(dict, key, key_len, hash);
    if (!item) {
        flock(dict->fd, LOCK_UN);
        return 0;
    }

    exptime = (lua_Number)(item->expires_at - now_ms()) / 1000.0;

    flock(dict->fd, LOCK_UN);

    if (exptime < 0)
        exptime = 0;

    lua_pushnumber(L, exptime);
    return 1;
}

/**
 * Update key expiration.
 *
 * When `exptime` is positive, the key expires after `exptime` seconds.
 * When `exptime` is `0` or negative, expiration is cleared.
 *
 * @function dict:expire
 * @tparam string key
 * @tparam number exptime Expiration in seconds.
 * @treturn boolean|nil ok `true` on success, `nil` if key does not exist.
 */
static int lua_dict_expire(lua_State *L)
{
    struct eco_shared_dict *dict = check_dict(L);
    size_t key_len;
    const char *key = luaL_checklstring(L, 2, &key_len);
    lua_Number exptime = luaL_checknumber(L, 3);
    struct item_hdr *item;
    uint32_t hash;

    luaL_argcheck(L, isfinite(exptime), 3, "exptime must be finite");

    if (flock(dict->fd, LOCK_EX))
        return push_errno(L, errno);

    hash = calc_key_hash(key, key_len);

    item = find_item(dict, key, key_len, hash);
    if (!item) {
        flock(dict->fd, LOCK_UN);
        return 0;
    }

    if (exptime > 0)
        item->expires_at = now_ms() + (int64_t)(exptime * 1000);
    else
        item->expires_at = 0;

    flock(dict->fd, LOCK_UN);
    lua_pushboolean(L, true);
    return 1;
}

/**
 * Flushes out all the items in the dictionary.
 *
 * @function dict:flush_all
 * @treturn nil
 */
static int lua_dict_flush_all(lua_State *L)
{
    struct eco_shared_dict *dict = check_dict(L);

    if (flock(dict->fd, LOCK_EX))
        return push_errno(L, errno);

    dict->hdr->len = 0;

    flock(dict->fd, LOCK_UN);
    return 0;
}

/**
 * Get all keys in the dictionary.
 *
 * @function dict:get_keys
 * @treturn table keys
 */
static int lua_dict_get_keys(lua_State *L)
{
    struct eco_shared_dict *dict = check_dict(L);
    struct shm_hdr *hdr = dict->hdr;
    size_t offset = 0;
    int i = 1;

    lua_newtable(L);

    if (flock(dict->fd, LOCK_SH))
        return push_errno(L, errno);

    while (offset < hdr->len) {
        struct item_hdr *item = (struct item_hdr *)(hdr->base + offset);

        if (!item_is_dead(item)) {
            lua_pushlstring(L, item->key, item->key_len);
            lua_rawseti(L, -2, i++);
        }

        offset += item_size(item);
    }

    flock(dict->fd, LOCK_UN);
    return 1;

}

/**
 * Close the dictionary and release associated resources.
 *
 * This is idempotent and is also invoked by `__gc` and `__close`.
 *
 * For dictionaries created by @{new}, closing also removes the backing
 * shared-memory file. Existing processes that already opened the
 * dictionary may continue to access it, but future @{get} calls by name fail.
 *
 * @function dict:close
 * @treturn nil
 */
static int lua_dict_close(lua_State *L)
{
    struct eco_shared_dict *dict = check_dict(L);

    if (dict->hdr) {
        munmap(dict->hdr, dict->map_size);
        dict->hdr = NULL;
    }

    if (dict->fd >= 0) {
        close(dict->fd);
        dict->fd = -1;
    }

    if (dict->owner) {
        unlink(dict->path);
        dict->owner = false;
    }

    return 0;
}

/// @section end

static const luaL_Reg methods[] = {
    {"del", lua_dict_del},
    {"set", lua_dict_set},
    {"get", lua_dict_get},
    {"incr", lua_dict_incr},
    {"ttl", lua_dict_ttl},
    {"expire", lua_dict_expire},
    {"flush_all", lua_dict_flush_all},
    {"get_keys", lua_dict_get_keys},
    {"close", lua_dict_close},
    {NULL, NULL}
};

static const luaL_Reg metatable[] = {
    {"__gc", lua_dict_close},
    {"__close", lua_dict_close},
    {NULL, NULL}
};

static int lua_shared_open(lua_State *L, const char *name, bool create, size_t size)
{
    int flags = O_RDWR | O_CLOEXEC;
    struct eco_shared_dict *dict;
    struct shm_hdr *hdr;
    size_t map_size = 0;
    void *map = NULL;
    struct stat st;
    char path[256];
    int fd;

    if (strchr(name, '/')) {
        lua_pushnil(L);
        lua_pushliteral(L, "invalid name");
        return 2;
    }

    snprintf(path, sizeof(path), "/dev/shm/eco-shared-%s.shm", name);

    if (create)
        flags |= O_CREAT | O_EXCL;

    fd = open(path, flags, 0666);
    if (fd < 0)
        return push_errno(L, errno);

    if (flock(fd, LOCK_EX)) {
        push_errno(L, errno);
        close(fd);
        return 2;
    }

    if (create) {
        map_size = sizeof(struct shm_hdr) + size;
        if (ftruncate(fd, map_size))
            goto err1;
    }

    if (fstat(fd, &st))
        goto err1;

    if (st.st_size < sizeof(struct shm_hdr)) {
        lua_pushnil(L);
        lua_pushliteral(L, "invalid shared memory file");
        goto err2;
    }

    map_size = st.st_size;
    map = mmap(NULL, map_size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (map == MAP_FAILED)
        goto err1;

    hdr = (struct shm_hdr *)map;

    if (create) {
        memset(map, 0, map_size);
        hdr->magic = SHARED_MAGIC;
    } else if (hdr->magic != SHARED_MAGIC) {
        lua_pushnil(L);
        lua_pushliteral(L, "invalid shared memory header");
        goto err2;
    }

    dict = lua_newuserdatauv(L, sizeof(struct eco_shared_dict), 0);
    luaL_setmetatable(L, SHARED_MT);

    memset(dict, 0, sizeof(struct eco_shared_dict));

    dict->map_size = map_size;
    dict->hdr = hdr;
    dict->fd = fd;
    dict->owner = create;

    strncpy(dict->path, path, sizeof(dict->path) - 1);

    flock(fd, LOCK_UN);
    return 1;

err1:
    push_errno(L, errno);
err2:
    if (map && map != MAP_FAILED)
        munmap(map, map_size);
    flock(fd, LOCK_UN);
    close(fd);
    if (create)
        unlink(path);
    return 2;
}

/**
 * Create a new shared-memory dictionary.
 *
 * The caller becomes the owner of the shared-memory file. When the owner
 * closes this dict (or it is garbage-collected), the file is removed.
 *
 * @function new
 * @tparam string name Dictionary name.
 * @tparam integer size Size of the dictionary.
 * @treturn dict
 * @treturn[2] nil
 * @treturn[2] string err
 */
static int lua_shared_new(lua_State *L)
{
    const char *name = luaL_checkstring(L, 1);
    int size = luaL_checkinteger(L, 2);

    luaL_argcheck(L, size > 0, 2, "size must be great than 0");

    return lua_shared_open(L, name, true, size);
}

/**
 * Open an existing shared-memory dictionary.
 *
 * The returned dict is a non-owner handle and `close` will not remove
 * the shared-memory file.
 *
 * @function get
 * @tparam string name Dictionary name.
 * @treturn dict
 * @treturn[2] nil
 * @treturn[2] string err
 */
static int lua_shared_get(lua_State *L)
{
    const char *name = luaL_checkstring(L, 1);
    return lua_shared_open(L, name, false, 0);
}

static const luaL_Reg funcs[] = {
    {"new", lua_shared_new},
    {"get", lua_shared_get},
    {NULL, NULL}
};

int luaopen_eco_shared(lua_State *L)
{
    creat_metatable(L, SHARED_MT, metatable, methods);

    luaL_newlib(L, funcs);

    return 1;
}
