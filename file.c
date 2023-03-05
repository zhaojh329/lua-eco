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

#include <sys/sendfile.h>
#include <sys/statvfs.h>
#include <stdlib.h>
#include <unistd.h>
#include <dirent.h>
#include <libgen.h>
#include <fcntl.h>
#include <errno.h>

#include "bufio.h"
#include "eco.h"

#define ECO_FILE_DIR_MT "eco{file-dir}"

static int eco_file_open(lua_State *L)
{
    const char *pathname = luaL_checkstring(L, 1);
    int flags = luaL_optinteger(L, 2, 0);
    int mode = luaL_optinteger(L, 3, 0);
    int fd;

    fd = open(pathname, flags, mode);
    if (fd < 0) {
        lua_pushnil(L);
        lua_pushstring(L, strerror(errno));
        return 2;
    }

    lua_pushinteger(L, fd);
    return 1;
}

static int eco_file_close(lua_State *L)
{
    int fd = luaL_checkinteger(L, 1);
    int ret;

    ret = close(fd);
    if (ret < 0) {
        lua_pushboolean(L, false);
        lua_pushstring(L, strerror(errno));
        return 2;
    }

    lua_pushboolean(L, true);
    return 1;
}

static int eco_file_read(lua_State *L)
{
    int fd = luaL_checkinteger(L, 1);
    size_t n = luaL_checkinteger(L, 2);
    ssize_t ret;
    char *buf;

    if (n < 1)
        luaL_argerror(L, 2, "must be greater than 0");

    buf = malloc(n);
    if (!buf) {
        lua_pushnil(L);
        lua_pushstring(L, strerror(errno));
        return 2;
    }

again:
    ret = read(fd, buf, n);
    if (unlikely(ret < 0)) {
        if (errno == EINTR)
            goto again;
        free(buf);
        lua_pushnil(L);
        lua_pushstring(L, strerror(errno));
        return 2;
    }

    lua_pushlstring(L, buf, ret);
    free(buf);

    return 1;
}

static int eco_file_read_to_buffer(lua_State *L)
{
    int fd = luaL_checkinteger(L, 1);
    struct eco_bufio *b = luaL_checkudata(L, 2, ECO_BUFIO_MT);
    size_t n = buffer_room(b);
    ssize_t ret;

    if (n == 0) {
        lua_pushnil(L);
        lua_pushliteral(L, "buffer is full");
        return 2;
    }

again:
    ret = read(fd, b->data + b->w, n);
    if (unlikely(ret < 0)) {
        if (errno == EINTR)
            goto again;
        lua_pushnil(L);
        lua_pushstring(L, strerror(errno));
        return 2;
    }

    b->w += ret;
    lua_pushinteger(L, ret);

    return 1;
}

static int eco_file_write_data(lua_State *L, int fd, const void *data, size_t len)
{
    ssize_t ret;

again:
    ret = write(fd, data, len);
    if (unlikely(ret < 0)) {
        if (errno == EINTR)
            goto again;
        lua_pushnil(L);
        lua_pushstring(L, strerror(errno));
        return 2;
    }

    lua_pushnumber(L, ret);
    return 1;
}

static int eco_file_write(lua_State *L)
{
    int fd = luaL_checkinteger(L, 1);
    size_t len;
    const char *data = luaL_checklstring(L, 2, &len);

    return eco_file_write_data(L, fd, data, len);
}

static int eco_file_sendfile(lua_State *L)
{
    int out_fd = luaL_checkinteger(L, 1);
    int in_fd = luaL_checkinteger(L, 2);
    off_t offset = luaL_optinteger(L, 3, -1);
    size_t count = luaL_checkinteger(L, 4);
    ssize_t ret;

    if (offset < 0)
        ret = sendfile(out_fd, in_fd, NULL, count);
    else
        ret = sendfile(out_fd, in_fd, &offset, count);
    if (ret < 0) {
        lua_pushnil(L);
        lua_pushstring(L, strerror(errno));
        return 2;
    }

    lua_pushinteger(L, ret);

    if (offset > -1)
        lua_pushinteger(L, offset);
    else
        lua_pushnil(L);

    return 2;
}

static int eco_file_lseek(lua_State *L)
{
    int fd = luaL_checkinteger(L, 1);
    off_t offset = luaL_checkinteger(L, 2);
    size_t where = luaL_checkinteger(L, 3);

    offset = lseek(fd, offset, where);
    if (offset == -1) {
        lua_pushnil(L);
        lua_pushstring(L, strerror(errno));
        return 2;
    }

    lua_pushinteger(L, offset);
    return 1;
}

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

static int __eco_file_stat(lua_State *L, struct stat *st)
{
    lua_newtable(L);

    switch (st->st_mode & S_IFMT) {
    case S_IFBLK: lua_pushliteral(L, "BLK");  break;
    case S_IFCHR: lua_pushliteral(L, "CHR");  break;
    case S_IFDIR: lua_pushliteral(L, "DIR");  break;
    case S_IFIFO: lua_pushliteral(L, "FIFO"); break;
    case S_IFLNK: lua_pushliteral(L, "LNK");  break;
    case S_IFREG: lua_pushliteral(L, "REG");  break;
    case S_IFSOCK:lua_pushliteral(L, "SOCK"); break;
    default:      lua_pushliteral(L, "");     break;
    }
    lua_setfield(L, -2, "type");

    lua_pushint(L, st->st_atime);
    lua_setfield(L, -2, "atime");

    lua_pushint(L, st->st_mtime);
    lua_setfield(L, -2, "mtime");

    lua_pushint(L, st->st_ctime);
    lua_setfield(L, -2, "ctime");

    lua_pushuint(L, st->st_nlink);
    lua_setfield(L, -2, "nlink");

    lua_pushuint(L, st->st_uid);
    lua_setfield(L, -2, "uid");

    lua_pushuint(L, st->st_gid);
    lua_setfield(L, -2, "gid");

    lua_pushuint(L, st->st_size);
    lua_setfield(L, -2, "size");

    lua_pushuint(L, st->st_ino);
    lua_setfield(L, -2, "ino");

    return 1;
}

static int eco_file_stat(lua_State *L)
{
    const char *path = luaL_checkstring(L, 1);
    struct stat st;

    if (stat(path, &st)) {
        lua_pushnil(L);
        lua_pushstring(L, strerror(errno));
        return 2;
    }

    return __eco_file_stat(L, &st);
}

static int eco_file_fstat(lua_State *L)
{
    int fd = luaL_checkinteger(L, 1);
    struct stat st;

    if (fstat(fd, &st)) {
        lua_pushnil(L);
        lua_pushstring(L, strerror(errno));
        return 2;
    }

    return __eco_file_stat(L, &st);
}

/* get filesystem statistics in kibibytes */
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
    lua_pushnumber(L, s.f_blocks * s.f_frsize / 1024.0);

    /* available bytes */
    lua_pushnumber(L, s.f_bavail * s.f_frsize / 1024.0);

    /* used bytes */
    lua_pushnumber(L, (s.f_blocks - s.f_bfree) * s.f_frsize / 1024.0);

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
        struct stat st;

        lua_pushstring(L, e->d_name);
        snprintf(fullpath, sizeof(fullpath), "%s/%s", path, e->d_name);

        stat(fullpath, &st);
        __eco_file_stat(L, &st);

        return 2;
    }

    closedir(*d);

    *d = NULL;

    return 0;
}

static int eco_file_dir_gc(lua_State *L)
{
    DIR *d = *(DIR **)luaL_checkudata(L, 1, ECO_FILE_DIR_MT);

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

static const struct luaL_Reg dir_methods[] =  {
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

static int eco_file_dirname(lua_State *L)
{
    const char *path = luaL_checkstring(L, 1);
    char *buf = strdup(path);

    lua_pushstring(L, dirname(buf));
    free(buf);

    return 1;
}

static int eco_file_basename(lua_State *L)
{
    const char *path = luaL_checkstring(L, 1);
    char *buf = strdup(path);

    lua_pushstring(L, basename(buf));
    free(buf);

    return 1;
}

static int eco_file_sync(lua_State *L)
{
    sync();
    return 0;
}

int luaopen_eco_core_file(lua_State *L)
{
    lua_newtable(L);

    lua_add_constant(L, "O_RDONLY", O_RDONLY);
    lua_add_constant(L, "O_WRONLY", O_WRONLY);
    lua_add_constant(L, "O_RDWR", O_RDWR);

    lua_add_constant(L, "O_APPEND", O_APPEND);
    lua_add_constant(L, "O_CLOEXEC", O_CLOEXEC);
    lua_add_constant(L, "O_CREAT", O_CREAT);
    lua_add_constant(L, "O_EXCL", O_EXCL);
    lua_add_constant(L, "O_NOCTTY", O_NOCTTY);
    lua_add_constant(L, "O_NONBLOCK", O_NONBLOCK);
    lua_add_constant(L, "O_TRUNC", O_TRUNC);

    lua_add_constant(L, "S_IRWXU", S_IRWXU);
    lua_add_constant(L, "S_IRUSR", S_IRUSR);
    lua_add_constant(L, "S_IWUSR", S_IWUSR);
    lua_add_constant(L, "S_IXUSR", S_IXUSR);
    lua_add_constant(L, "S_IRWXG", S_IRWXG);
    lua_add_constant(L, "S_IRGRP", S_IRGRP);
    lua_add_constant(L, "S_IWGRP", S_IWGRP);
    lua_add_constant(L, "S_IXGRP", S_IXGRP);
    lua_add_constant(L, "S_IRWXO", S_IRWXO);
    lua_add_constant(L, "S_IROTH", S_IROTH);
    lua_add_constant(L, "S_IWOTH", S_IWOTH);
    lua_add_constant(L, "S_IXOTH", S_IXOTH);
    lua_add_constant(L, "S_ISUID", S_ISUID);
    lua_add_constant(L, "S_ISGID", S_ISGID);
    lua_add_constant(L, "S_ISVTX", S_ISVTX);

    lua_add_constant(L, "SEEK_SET", SEEK_SET);
    lua_add_constant(L, "SEEK_CUR", SEEK_CUR);
    lua_add_constant(L, "SEEK_END", SEEK_END);

    lua_pushcfunction(L, eco_file_open);
    lua_setfield(L, -2, "open");

    lua_pushcfunction(L, eco_file_close);
    lua_setfield(L, -2, "close");

    lua_pushcfunction(L, eco_file_read);
    lua_setfield(L, -2, "read");

    lua_pushcfunction(L, eco_file_read_to_buffer);
    lua_setfield(L, -2, "read_to_buffer");

    lua_pushcfunction(L, eco_file_write);
    lua_setfield(L, -2, "write");

    lua_pushcfunction(L, eco_file_sendfile);
    lua_setfield(L, -2, "sendfile");

    lua_pushcfunction(L, eco_file_lseek);
    lua_setfield(L, -2, "lseek");

    lua_pushcfunction(L, eco_file_access);
    lua_setfield(L, -2, "access");

    lua_pushcfunction(L, eco_file_readlink);
    lua_setfield(L, -2, "readlink");

    lua_pushcfunction(L, eco_file_stat);
    lua_setfield(L, -2, "stat");

    lua_pushcfunction(L, eco_file_fstat);
    lua_setfield(L, -2, "fstat");

    lua_pushcfunction(L, eco_file_statvfs);
    lua_setfield(L, -2, "statvfs");

    eco_new_metatable(L, ECO_FILE_DIR_MT, dir_methods);
    lua_pushcclosure(L, eco_file_dir, 1);
    lua_setfield(L, -2, "dir");

    lua_pushcfunction(L, eco_file_chown);
    lua_setfield(L, -2, "chown");

    lua_pushcfunction(L, eco_file_dirname);
    lua_setfield(L, -2, "dirname");

    lua_pushcfunction(L, eco_file_basename);
    lua_setfield(L, -2, "basename");

    lua_pushcfunction(L, eco_file_sync);
    lua_setfield(L, -2, "sync");

    return 1;
}
