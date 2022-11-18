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

#include <sys/statvfs.h>
#include <stdlib.h>
#include <unistd.h>
#include <dirent.h>
#include <errno.h>

#include "eco.h"

static int eco_file_access(lua_State *L)
{
    const char *file = luaL_checkstring(L, 1);
    const char *mode = lua_tostring(L, 2);
    int md = F_OK;

    if (mode) {
        if (strchr(mode, 'x'))
            md |= X_OK;
        else if (strchr(mode, 'w'))
            md |= W_OK;
        else if (strchr(mode, 'r'))
            md |= R_OK;
    }

    lua_pushboolean(L, !access(file, md));

    return 1;
}

static int eco_file_readlink(lua_State *L)
{
    const char *path = luaL_checkstring(L, 1);
    char buf[PATH_MAX] = "";
    ssize_t nbytes;

    nbytes = readlink(path, buf, PATH_MAX);
    if (nbytes < 0) {
        lua_pushnil(L);
        lua_pushstring(L, strerror(errno));
        return 2;
    }

    lua_pushlstring(L, buf, nbytes);

    return 1;
}

static int __eco_file_stat(lua_State *L, const char *path)
{
    struct stat st;

    if (stat(path, &st))
        return -1;

    lua_newtable(L);

    switch (st.st_mode & S_IFMT) {
    case S_IFBLK: lua_pushstring(L, "BLK");  break;
    case S_IFCHR: lua_pushstring(L, "CHR");  break;
    case S_IFDIR: lua_pushstring(L, "DIR");  break;
    case S_IFIFO: lua_pushstring(L, "FIFO"); break;
    case S_IFLNK: lua_pushstring(L, "LNK");  break;
    case S_IFREG: lua_pushstring(L, "REG");  break;
    case S_IFSOCK:lua_pushstring(L, "SOCK"); break;
    default:      lua_pushstring(L, "");     break;
    }
    lua_setfield(L, -2, "type");

    lua_pushint(L, st.st_atime);
    lua_setfield(L, -2, "atime");

    lua_pushint(L, st.st_mtime);
    lua_setfield(L, -2, "mtime");

    lua_pushint(L, st.st_ctime);
    lua_setfield(L, -2, "ctime");

    lua_pushuint(L, st.st_nlink);
    lua_setfield(L, -2, "nlink");

    lua_pushuint(L, st.st_uid);
    lua_setfield(L, -2, "uid");

    lua_pushuint(L, st.st_gid);
    lua_setfield(L, -2, "gid");

    lua_pushuint(L, st.st_size);
    lua_setfield(L, -2, "size");

    return 0;
}

static int eco_file_stat(lua_State *L)
{
    const char *path = luaL_checkstring(L, 1);

    if (__eco_file_stat(L, path)) {
        lua_pushnil(L);
        lua_pushstring(L, strerror(errno));
        return 2;
    }

    return 1;
}

static int eco_file_statvfs(lua_State *L)
{
    const char *path = luaL_checkstring(L, 1);
    struct statvfs s;

    if (statvfs(path, &s)) {
        lua_pushnil(L);
        lua_pushstring(L, strerror(errno));
        return 2;
    }

    /* total bytes */
    lua_pushuint(L, s.f_blocks * s.f_frsize);

    /* available bytes */
    lua_pushuint(L, s.f_bavail * s.f_frsize);

    /* used bytes */
    lua_pushuint(L, (s.f_blocks - s.f_bfree) * s.f_frsize);

    return 3;
}

static int eco_file_dir_iter(lua_State *L)
{
    DIR **d = (DIR **)lua_touserdata(L, lua_upvalueindex(1));
    char fullpath[PATH_MAX];
    const char *path;
    struct dirent *e;

    if (!*d)
        return 0;

    lua_pushvalue(L, lua_upvalueindex(2));
    path = lua_tostring(L, -1);

    if ((e = readdir(*d))) {
        lua_pushstring(L, e->d_name);
        snprintf(fullpath, sizeof(fullpath), "%s/%s", path, e->d_name);
        __eco_file_stat(L, fullpath);
        return 2;
    }

    closedir(*d);

    *d = NULL;

    return 0;
}

static int eco_file_dir_gc(lua_State *L)
{
    DIR *d = *(DIR **)lua_touserdata(L, 1);

    if (d)
        closedir(d);

    return 0;
}

static int eco_file_dir(lua_State *L)
{
    const char *path = luaL_checkstring(L, 1);
    DIR **d = (DIR **)lua_newuserdata(L, sizeof(DIR *));

    lua_pushvalue(L, lua_upvalueindex(1));
    lua_setmetatable(L, -2);

    lua_pushstring(L, path);

    *d = opendir(path);

    lua_pushcclosure(L, eco_file_dir_iter, 2);

    return 1;
}

static const struct luaL_Reg dir_metatable[] =  {
    {"__gc", eco_file_dir_gc},
    {NULL, NULL}
};

static int eco_file_chown(lua_State *L)
{
    const char *pathname = luaL_checkstring(L, 1);
    uid_t uid = -1;
    gid_t gid = -1;

    if (lua_isnumber(L, 2))
        uid = (uid_t)lua_tointeger(L, 2);

    if (lua_isnumber(L, 3))
        gid = (gid_t)lua_tointeger(L, 3);

    if (chown(pathname, uid, gid)) {
        lua_pushnil(L);
        lua_pushstring(L, strerror(errno));
        return 2;
    }

    lua_pushboolean(L, true);

    return 1;
}

int luaopen_eco_file(lua_State *L)
{
    lua_newtable(L);

    lua_pushcfunction(L, eco_file_access);
    lua_setfield(L, -2, "access");

    lua_pushcfunction(L, eco_file_readlink);
    lua_setfield(L, -2, "readlink");

    lua_pushcfunction(L, eco_file_stat);
    lua_setfield(L, -2, "stat");

    lua_pushcfunction(L, eco_file_statvfs);
    lua_setfield(L, -2, "statvfs");

    eco_new_metatable(L, dir_metatable);
    lua_pushcclosure(L, eco_file_dir, 1);
    lua_setfield(L, -2, "dir");

    lua_pushcfunction(L, eco_file_chown);
    lua_setfield(L, -2, "chown");

    return 1;
}
