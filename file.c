/* SPDX-License-Identifier: MIT */
/*
 * Author: Jianhui Zhao <zhaojh329@gmail.com>
 */

/**
 * @module eco.file
 */

#include <sys/statvfs.h>
#include <sys/inotify.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <dirent.h>
#include <libgen.h>
#include <fcntl.h>
#include <errno.h>

#include "eco.h"

#define ECO_FILE_DIR_MT "eco{file-dir}"

/**
 * Create a directory.
 * Calls the underlying POSIX `mkdir(2)` function.
 * @function mkdir
 * @tparam string pathname Path of the directory to create.
 * @tparam[opt=0777] int mode Permission bits for the new directory (before umask).
 * @treturn boolean true On success.
 * @treturn[2] nil On failure.
 * @treturn[2] string Error message when failed.
 * @usage
 * local ok, err = file.mkdir('/tmp/test', 0755)
 * if not ok then
 *     print('mkdir failed:', err)
 * end
 */
static int lua_file_mkdir(lua_State *L)
{
    const char *pathname = luaL_checkstring(L, 1);
    int mode = luaL_optinteger(L, 2, 0777);

    luaL_argcheck(L, mode >= 0, 2, "invalid mode");

    if (mkdir(pathname, mode)) {
        lua_pushnil(L);
        lua_pushstring(L, strerror(errno));
        return 2;
    }

    lua_pushboolean(L, true);
    return 1;
}

static int lua_file_open(lua_State *L)
{
    const char *pathname = luaL_checkstring(L, 1);
    int flags = luaL_optinteger(L, 2, O_RDONLY);
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

static int lua_file_close(lua_State *L)
{
    int fd = luaL_checkinteger(L, 1);
    int ret;

    ret = close(fd);
    if (ret < 0) {
        lua_pushnil(L);
        lua_pushstring(L, strerror(errno));
        return 2;
    }

    lua_pushboolean(L, true);
    return 1;
}

static int lua_read(lua_State *L)
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

static int lua_write(lua_State *L)
{
    int fd = luaL_checkinteger(L, 1);
    size_t len;
    const char *data = luaL_checklstring(L, 2, &len);
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

    lua_pushinteger(L, ret);
    return 1;
}

static int lua_lseek(lua_State *L)
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

/**
 * Test file accessibility.
 *
 * Thin wrapper around POSIX `access(2)`.
 *
 * @function access
 * @tparam string file Path to test.
 * @tparam[opt] string mode Access mode string: contains `r`, `w`, or `x`.
 *   If omitted, checks existence (`F_OK`).
 * @treturn boolean `true` if accessible, otherwise `false`.
 */
static int lua_access(lua_State *L)
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

/**
 * Read value of a symbolic link.
 *
 * Thin wrapper around POSIX `readlink(2)`.
 *
 * @function readlink
 * @tparam string path Symbolic link path.
 * @treturn string Link target.
 * @treturn[2] nil On failure.
 * @treturn[2] string Error message.
 */
static int lua_readlink(lua_State *L)
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

static int __lua_file_stat(lua_State *L, struct stat *st)
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

    lua_pushinteger(L, st->st_mode & 0777);
    lua_setfield(L, -2, "mode");

    lua_pushinteger(L, st->st_atime);
    lua_setfield(L, -2, "atime");

    lua_pushinteger(L, st->st_mtime);
    lua_setfield(L, -2, "mtime");

    lua_pushinteger(L, st->st_ctime);
    lua_setfield(L, -2, "ctime");

    lua_pushinteger(L, st->st_nlink);
    lua_setfield(L, -2, "nlink");

    lua_pushinteger(L, st->st_uid);
    lua_setfield(L, -2, "uid");

    lua_pushinteger(L, st->st_gid);
    lua_setfield(L, -2, "gid");

    lua_pushinteger(L, st->st_size);
    lua_setfield(L, -2, "size");

    lua_pushinteger(L, st->st_ino);
    lua_setfield(L, -2, "ino");

    return 1;
}

/**
 * Get file status by path.
 *
 * Thin wrapper around POSIX `stat(2)`.
 *
 * @function stat
 * @tparam string path Path to file.
 * @treturn table Info table with fields: `type`, `mode`, `atime`, `mtime`,
 *   `ctime`, `nlink`, `uid`, `gid`, `size`, `ino`.
 * @treturn[2] nil On failure.
 * @treturn[2] string Error message.
 */
static int lua_stat(lua_State *L)
{
    const char *path = luaL_checkstring(L, 1);
    struct stat st;

    if (stat(path, &st)) {
        lua_pushnil(L);
        lua_pushstring(L, strerror(errno));
        return 2;
    }

    return __lua_file_stat(L, &st);
}

/**
 * Get file status by file descriptor.
 *
 * Thin wrapper around POSIX `fstat(2)`.
 *
 * @function fstat
 * @tparam int fd File descriptor.
 * @treturn table See @{stat}.
 * @treturn[2] nil On failure.
 * @treturn[2] string Error message.
 */
static int lua_fstat(lua_State *L)
{
    int fd = luaL_checkinteger(L, 1);
    struct stat st;

    if (fstat(fd, &st)) {
        lua_pushnil(L);
        lua_pushstring(L, strerror(errno));
        return 2;
    }

    return __lua_file_stat(L, &st);
}

/**
 * Get filesystem statistics.
 *
 * Thin wrapper around `statvfs(3)`.
 * The returned values are in KiB (kibibytes).
 *
 * @function statvfs
 * @tparam string path Any path on the target filesystem.
 * @treturn number Total size in KiB.
 * @treturn number Available size in KiB for unprivileged processes.
 * @treturn number Used size in KiB.
 * @treturn[2] nil On failure.
 * @treturn[2] string Error message.
 */
/* get filesystem statistics in kibibytes */
static int lua_statvfs(lua_State *L)
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
    const char *path = lua_tostring(L, lua_upvalueindex(1));
    DIR **d = (DIR **)lua_touserdata(L, 1);
    char fullpath[PATH_MAX];
    struct dirent *e;

    if (!*d)
        return 0;

again:
    if ((e = readdir(*d))) {
        struct stat st;

        if (!strcmp(e->d_name, ".") || !strcmp(e->d_name, ".."))
            goto again;

        lua_pushstring(L, e->d_name);
        snprintf(fullpath, sizeof(fullpath), "%s/%s", path, e->d_name);

        stat(fullpath, &st);
        __lua_file_stat(L, &st);

        return 2;
    }

    closedir(*d);

    *d = NULL;

    return 0;
}

static int eco_file_dir_gc(lua_State *L)
{
    DIR **d = (DIR **)luaL_checkudata(L, 1, ECO_FILE_DIR_MT);

    if (*d) {
        closedir(*d);
        *d = NULL;
    }

    return 0;
}

/**
 * Iterate a directory.
 *
 * Convenience iterator around `opendir(3)` / `readdir(3)`.
 * Each iteration returns entry name and a @{stat} style info table.
 *
 * @function dir
 * @tparam string path Directory path.
 * @treturn function Iterator function.
 * @treturn any Iterator state.
 * @treturn any Iterator initial value.
 * @treturn any A closeable userdata (for `__close`).
 *
 * @usage
 * for name, info in file.dir('/tmp') do
 *     print(name, info.type, info.size)
 * end
 */
static int lua_file_dir(lua_State *L)
{
    const char *path = luaL_checkstring(L, 1);
    DIR **d = (DIR **)lua_newuserdata(L, sizeof(DIR *));

    luaL_setmetatable(L, ECO_FILE_DIR_MT);

    *d = opendir(path);

    lua_rotate(L, 1, 1);

    lua_pushcclosure(L, eco_file_dir_iter, 1);

    lua_rotate(L, 1, 1);

    lua_pushnil(L);

    lua_pushvalue(L, -2);

    return 4;
}

static const struct luaL_Reg dir_mt[] =  {
    {"__gc", eco_file_dir_gc},
    {"__close", eco_file_dir_gc},
    {NULL, NULL}
};

/**
 * Change owner and group of a file.
 *
 * Thin wrapper around POSIX `chown(2)`.
 * To keep a value unchanged, pass `nil` for that argument.
 *
 * @function chown
 * @tparam string pathname Path of the file.
 * @tparam[opt] int uid New user id, or `nil` to keep.
 * @tparam[opt] int gid New group id, or `nil` to keep.
 * @treturn boolean true On success.
 * @treturn[2] nil On failure.
 * @treturn[2] string Error message.
 */
static int lua_chown(lua_State *L)
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

/**
 * Get directory part of a path.
 *
 * Wrapper around `dirname(3)`.
 *
 * @function dirname
 * @tparam string path Input path.
 * @treturn string Directory component.
 */
static int lua_dirname(lua_State *L)
{
    const char *path = luaL_checkstring(L, 1);
    char *buf = strdup(path);

    lua_pushstring(L, dirname(buf));
    free(buf);

    return 1;
}

/**
 * Get last path component.
 *
 * Wrapper around `basename(3)`.
 *
 * @function basename
 * @tparam string path Input path.
 * @treturn string Base name.
 */
static int lua_basename(lua_State *L)
{
    const char *path = luaL_checkstring(L, 1);
    char *buf = strdup(path);

    lua_pushstring(L, basename(buf));
    free(buf);

    return 1;
}

static int lua_flock(lua_State *L)
{
    int fd = luaL_checkinteger(L, 1);
    int operation = luaL_checkinteger(L, 2);

    if (flock(fd, operation | LOCK_NB)) {
        lua_pushnil(L);
        lua_pushinteger(L, errno);
        return 2;
    }

    lua_pushboolean(L, true);

    return 1;
}

static int lua_inotify_init(lua_State *L)
{
    int fd = inotify_init1(IN_NONBLOCK | IN_CLOEXEC);
    if (fd < 0) {
        lua_pushnil(L);
        lua_pushstring(L, strerror(errno));
        return 2;
    }

    lua_pushinteger(L, fd);
    return 1;
}

static int lua_inotify_add_watch(lua_State *L)
{
    int fd = luaL_checkinteger(L, 1);
    const char *pathname = luaL_checkstring(L, 2);
    uint32_t mask = luaL_checkinteger(L, 3);
    int wd;

    wd = inotify_add_watch(fd, pathname, mask);
    if (wd < 0) {
        lua_pushnil(L);
        lua_pushstring(L, strerror(errno));
        return 2;
    }

    lua_pushinteger(L, wd);
    return 1;
}

static int lua_inotify_rm_watch(lua_State *L)
{
    int fd = luaL_checkinteger(L, 1);
    int wd = luaL_checkinteger(L, 2);

    if (inotify_rm_watch(fd, wd)) {
        lua_pushnil(L);
        lua_pushstring(L, strerror(errno));
        return 2;
    }

    lua_pushboolean(L, true);
    return 1;
}

static int lua_inotify_parse_event(lua_State *L)
{
    size_t len;
    const char *buf = luaL_checklstring(L, 1, &len);
    int i = 0, n = 1;

    lua_newtable(L);

    while (i < len) {
        struct inotify_event *event = (struct inotify_event *)&buf[i];

        lua_newtable(L);

        lua_pushinteger(L, event->wd);
        lua_setfield(L, -2, "wd");

        lua_pushinteger(L, event->mask);
        lua_setfield(L, -2, "mask");

        if (event->len > 0) {
            lua_pushstring(L, event->name);
            lua_setfield(L, -2, "name");
        }

        lua_rawseti(L, -2, n++);

        i += sizeof(struct inotify_event) + event->len;
    }

    return 1;
}

static const luaL_Reg funcs[] = {
    {"mkdir", lua_file_mkdir},
    {"open", lua_file_open},
    {"close", lua_file_close},
    {"read", lua_read},
    {"write", lua_write},
    {"lseek", lua_lseek},
    {"access", lua_access},
    {"readlink", lua_readlink},
    {"stat", lua_stat},
    {"fstat", lua_fstat},
    {"statvfs", lua_statvfs},
    {"chown", lua_chown},
    {"dirname", lua_dirname},
    {"basename", lua_basename},
    {"flock", lua_flock},
    {"dir", lua_file_dir},
    {"inotify_init", lua_inotify_init},
    {"inotify_add_watch", lua_inotify_add_watch},
    {"inotify_rm_watch", lua_inotify_rm_watch},
    {"inotify_parse_event", lua_inotify_parse_event},
    {NULL, NULL}
};

int luaopen_eco_internal_file(lua_State *L)
{
    creat_metatable(L, ECO_FILE_DIR_MT, dir_mt, NULL);

    luaL_newlib(L, funcs);

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

    lua_add_constant(L, "LOCK_SH", LOCK_SH);
    lua_add_constant(L, "LOCK_EX", LOCK_EX);
    lua_add_constant(L, "LOCK_UN", LOCK_UN);

    /* inotify */
    lua_add_constant(L, "IN_ACCESS", IN_ACCESS);
    lua_add_constant(L, "IN_MODIFY", IN_MODIFY);
    lua_add_constant(L, "IN_ATTRIB", IN_ATTRIB);
    lua_add_constant(L, "IN_CLOSE_WRITE", IN_CLOSE_WRITE);
    lua_add_constant(L, "IN_CLOSE_NOWRITE", IN_CLOSE_NOWRITE);
    lua_add_constant(L, "IN_CLOSE", IN_CLOSE);
    lua_add_constant(L, "IN_OPEN", IN_OPEN);
    lua_add_constant(L, "IN_MOVED_FROM", IN_MOVED_FROM);
    lua_add_constant(L, "IN_MOVED_TO", IN_MOVED_TO);
    lua_add_constant(L, "IN_MOVE", IN_MOVE);
    lua_add_constant(L, "IN_CREATE", IN_CREATE);
    lua_add_constant(L, "IN_DELETE", IN_DELETE);
    lua_add_constant(L, "IN_DELETE_SELF", IN_DELETE_SELF);
    lua_add_constant(L, "IN_MOVE_SELF", IN_MOVE_SELF);
    lua_add_constant(L, "IN_ALL_EVENTS", IN_ALL_EVENTS);
    lua_add_constant(L, "IN_ISDIR", IN_ISDIR);

    return 1;
}
