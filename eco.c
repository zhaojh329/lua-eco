/* SPDX-License-Identifier: MIT */
/*
 * Author: Jianhui Zhao <zhaojh329@gmail.com>
 */

/// @module eco

#include <sys/sendfile.h>
#include <sys/epoll.h>
#include <sys/time.h>
#include <stdbool.h>
#include <unistd.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <time.h>

#include "config.h"
#include "eco.h"
#include "list.h"

static char eco_scheduler_key;
static char eco_co_key;

#define MAX_EVENTS 128

#define MAX_TIMER_CACHE 32

#define ECO_IO_MT "struct eco_io *"
#define ECO_BUFFER_MT "struct eco_buf *"
#define ECO_READER_MT "struct eco_reader *"
#define ECO_WRITER_MT "struct eco_writer *"

struct eco_scheduler {
    struct list_head timer_cache;
    struct list_head timers;
    size_t timer_cache_size;
    int panic_hook;
    int epoll_fd;
    bool quit;
};

struct eco_timer {
    struct list_head list;
    uint64_t at;
    lua_State *co;
};

struct eco_buffer {
    size_t size;
    size_t len;
    uint8_t buf[];
};

struct eco_io {
    struct eco_timer timer;
    unsigned is_timeout:1;
    unsigned is_canceled:1;
    double timeout;
    lua_State *co;
    int fd;
};

struct eco_reader {
    struct eco_io io;
    size_t expected;
    void *buf;
    int (*read)(void *buf, size_t len, void *ctx, char **err);
    void *ctx;
};

struct eco_writer {
    struct eco_io io;
    union {
        struct {
            const char *data;
            int ref;
        } data;
        struct {
            off_t offset;
            int fd;
        } file;
    };
    size_t total;
    size_t written;
    int (*write)(const void *buf, size_t len, void *ctx, char **err);
    void *ctx;
};

static int eco_scheduler_init(lua_State *L)
{
    struct eco_scheduler *sched = calloc(1, sizeof(struct eco_scheduler));
    if (!sched)
        return luaL_error(L, "failed to allocate scheduler");

    sched->epoll_fd = epoll_create1(0);
    if (sched->epoll_fd < 0) {
        free(sched);
        return luaL_error(L, "failed to create epoll: %s", strerror(errno));
    }

    sched->panic_hook = LUA_NOREF;
    sched->quit = false;

    INIT_LIST_HEAD(&sched->timer_cache);
    INIT_LIST_HEAD(&sched->timers);

    lua_pushlightuserdata(L, sched);
    lua_rawsetp(L, LUA_REGISTRYINDEX, &eco_scheduler_key);

    lua_newtable(L);
    lua_rawsetp(L, LUA_REGISTRYINDEX, &eco_co_key);

    return 0;
}

static struct eco_scheduler *get_eco_scheduler(lua_State *L)
{
    struct eco_scheduler *sched;

    lua_rawgetp(L, LUA_REGISTRYINDEX, &eco_scheduler_key);

    sched = (struct eco_scheduler *)lua_topointer(L, -1);

    lua_pop(L, 1);

    return sched;
}

static void eco_resume(lua_State *L, lua_State *co, int narg)
{
    struct eco_scheduler *sched;
    int nres, status;

    status = lua_resume(co, L, narg, &nres);
    switch (status) {
    case LUA_OK: /* dead */
        set_obj(L, &eco_co_key, 0, co);
        break;

    case LUA_YIELD:
        break;

    default:
        sched = get_eco_scheduler(L);

        luaL_traceback(L, co, lua_tostring(co, -1), 0);
        luaL_traceback(L, L, NULL, 0);

        if (sched->panic_hook != LUA_NOREF) {
            lua_rawgeti(L, LUA_REGISTRYINDEX, sched->panic_hook);
            lua_insert(L, -3);
            lua_call(L, 2, 0);
        } else {
            printf("%s\n", lua_tostring(L, -2));
            printf("%s\n", lua_tostring(L, -1));
        }

        exit(1);
    }
}

static void eco_resume_io(lua_State *L, struct eco_io *io)
{
    lua_State *co = io->co;

    if (!co)
        return;

    io->co = NULL;

    eco_resume(L, co, 0);
}

static uint64_t eco_time_now()
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

static void eco_timer_start(struct eco_scheduler *sched, lua_State *L,
            struct eco_timer *timer, double seconds)
{
    struct list_head *h = &sched->timers;
    struct eco_timer *pos;

    timer->at = eco_time_now() + (uint64_t)(seconds * 1000);

    list_for_each_entry(pos, &sched->timers, list) {
        if (pos->at > timer->at) {
            h = &pos->list;
            break;
        }
    }

    list_add_tail(&timer->list, h);

    timer->co = L;
}

static void eco_timer_stop(struct eco_timer *timer)
{
    if (!timer->at)
        return;

    timer->at = 0;
    timer->co = NULL;

    list_del(&timer->list);
}

static struct eco_timer *eco_timer_alloc(struct eco_scheduler *sched)
{
    struct eco_timer *timer;

    if (list_empty(&sched->timer_cache)) {
        timer = malloc(sizeof(struct eco_timer));
        if (!timer)
            return NULL;
    } else {
        timer = (struct eco_timer *)list_first_entry(&sched->timer_cache, struct eco_timer, list);
        list_del(&timer->list);
        sched->timer_cache_size--;
    }

    timer->at = 0;
    timer->co = NULL;

    return timer;
}

static void eco_timer_free(struct eco_scheduler *sched, struct eco_timer *timer)
{
    eco_timer_stop(timer);

    if (sched->timer_cache_size < MAX_TIMER_CACHE) {
        list_add_tail(&timer->list, &sched->timer_cache);
        sched->timer_cache_size++;
    } else {
        free(timer);
    }
}

static int set_fd_nonblock(int fd)
{
    int flags = fcntl(fd, F_GETFL);
    if (flags < 0)
        return -1;

    if (flags & O_NONBLOCK)
        return 0;

    return fcntl(fd, F_SETFL, flags | O_NONBLOCK);
}

static int epoll_ctl_io(lua_State *L, struct eco_io *io, int events, int op)
{
    struct eco_scheduler *sched = get_eco_scheduler(L);
    struct eco_timer *timer = &io->timer;
    struct epoll_event ev;
    int ret;

    if (op == EPOLL_CTL_DEL)
        eco_timer_stop(timer);

    ev.events = events | EPOLLERR | EPOLLHUP;
    ev.data.ptr = io;

    ret = epoll_ctl(sched->epoll_fd, op, io->fd, &ev);
    if (ret < 0)
        return -1;

    if (op == EPOLL_CTL_ADD) {
        io->co = L;
        if (io->timeout > 0)
            eco_timer_start(sched, NULL, timer, io->timeout);
    }

    return 0;
}

static inline int epoll_ctl_io_read(lua_State *L, struct eco_io *io)
{
    return epoll_ctl_io(L, io, EPOLLIN, EPOLL_CTL_ADD);
}

static inline int epoll_ctl_io_write(lua_State *L, struct eco_io *io)
{
    return epoll_ctl_io(L, io, EPOLLOUT, EPOLL_CTL_ADD);
}

static inline int epoll_ctl_io_del(lua_State *L, struct eco_io *io)
{
    return epoll_ctl_io(L, io, 0, EPOLL_CTL_DEL);
}

static int lua_io_readk(lua_State *L, struct eco_io *io, void *dst, size_t len, lua_KFunction k)
{
    int ret;

    if (io->is_timeout) {
        io->is_timeout = 0;
        lua_pushnil(L);
        lua_pushliteral(L, "timeout");
        return -1;
    }

    if (io->is_canceled) {
        io->is_canceled = 0;
        epoll_ctl_io_del(L, io);
        lua_pushnil(L);
        lua_pushliteral(L, "canceled");
        return -1;
    }

    ret = read(io->fd, dst, len);
    if (ret < 0) {
        if (errno == EAGAIN || errno == EWOULDBLOCK) {
            io->co = L;
            return lua_yieldk(L, 0, (lua_KContext)io, k);
        }
        goto err;
    }

    epoll_ctl_io_del(L, io);

    return ret;

err:
    lua_pushnil(L);
    lua_pushstring(L, strerror(errno));
    epoll_ctl_io_del(L, io);
    return -1;
}

static int lua_io_read(lua_State *L, struct eco_io *io, void *dst, size_t len, lua_KFunction k)
{
    int ret = read(io->fd, dst, len);
    if (ret < 0) {
        if (errno == EAGAIN || errno == EWOULDBLOCK) {
            if (epoll_ctl_io_read(L, io) < 0)
                goto err;
            return lua_yieldk(L, 0, (lua_KContext)io, k);
        }
        goto err;
    }

    return ret;

err:
    lua_pushnil(L);
    lua_pushstring(L, strerror(errno));
    return -1;
}

static int lua_io_waitk(lua_State *L, int status, lua_KContext ctx)
{
    struct eco_io *io = (struct eco_io *)ctx;

    if (io->is_timeout) {
        io->is_timeout = 0;
        lua_pushnil(L);
        lua_pushliteral(L, "timeout");
        return 2;
    }

    if (io->is_canceled) {
        io->is_canceled = 0;
        epoll_ctl_io_del(L, io);
        lua_pushnil(L);
        lua_pushliteral(L, "canceled");
        return 2;
    }

    epoll_ctl_io_del(L, io);
    lua_pushboolean(L, true);
    return 1;
}

/**
 * io handle returned by @{io}.
 * @type io
 */

/**
 * Wait for the I/O object to become ready.
 *
 * Suspends the current coroutine until the file descriptor is ready
 * for reading (EPOLLIN) or writing (EPOLLOUT), or until an optional timeout.
 *
 * @function io:wait
 * @tparam int ev Event mask: @{eco.READ}, @{eco.WRITE}, or a combination.
 * @tparam[opt] number timeout Timeout in seconds (default nil = no timeout).
 * @treturn boolean true If the I/O object is ready.
 * @treturn[2] nil On error.
 * @treturn[2] string Error message.
 */
static int lua_io_wait(lua_State *L)
{
    struct eco_io *io = luaL_checkudata(L, 1, ECO_IO_MT);
    int ev = luaL_checkinteger(L, 2);
    double timeout = lua_tonumber(L, 3);

    if (ev == 0 || (ev & ~(EPOLLIN | EPOLLOUT)))
        return luaL_argerror(L, 2, "invalid");

    if (io->co)
        luaL_error(L, "another coroutine is already waiting for I/O on this file descriptor");

    io->timeout = timeout;

    if (epoll_ctl_io(L, io, ev, EPOLL_CTL_ADD)) {
        lua_pushnil(L);
        lua_pushstring(L, strerror(errno));
        return 2;
    }

    return lua_yieldk(L, 0, (lua_KContext)io, lua_io_waitk);
}

/**
 * Cancel a pending wait on this I/O object.
 *
 * If a coroutine is currently suspended in `io:wait()`, it will be resumed
 * immediately and `io:wait()` will return nil, "canceled".
 *
 * @function io:cancel
 * @treturn nil
 *
 * @usage
 * local io = eco.io(fd)
 * eco.run(function()
 *     local ok, err = io:wait(eco.READ)
 *     if not ok then print('Wait failed or canceled:', err) end
 * end)
 *
 * io:cancel()
 */
static int lua_io_cancel(lua_State *L)
{
    struct eco_io *io = luaL_checkudata(L, 1, ECO_IO_MT);

    if (!io->co)
        return 0;

    io->is_canceled = 1;
    eco_resume_io(L, io);

    return 0;
}

/// @section end

static const struct luaL_Reg io_methods[] = {
    {"wait", lua_io_wait},
    {"cancel", lua_io_cancel},
    {NULL, NULL}
};

/**
 * buffer handle returned by @{buffer}.
 * @type buffer
 */

/**
 * Get raw data from the buffer.
 *
 * Returns a string containing `count` bytes starting from `start` position.
 * If arguments are omitted, returns the entire buffer content.
 *
 * @function buffer:data
 * @tparam[opt] int start Starting index (default 0)
 * @tparam[opt] int count Number of bytes to read (default full length)
 * @treturn string Data from the buffer
 */
static int lua_buffer_data(lua_State *L)
{
    struct eco_buffer *b = luaL_checkudata(L, 1, ECO_BUFFER_MT);
    int top = lua_gettop(L);
    int count = b->len;
    int start = 0;

    switch (top) {
    case 3:
        count = luaL_checkinteger(L, 3);
        if (count > b->len)
            count = b->len;
    case 2:
        start = luaL_checkinteger(L, 2);
        break;
    case 1:
        break;
    default:
        return luaL_error(L, "invalid argument");
    }

    lua_pushlstring(L, (const char *)(b->buf + start), count);
    return 1;
}

static void eco_buffer_consume(struct eco_buffer *b, size_t len)
{
    memmove(b->buf, b->buf + len, b->len - len);
    b->len -= len;
}

/**
 * Read and remove bytes from the start of the buffer.
 *
 * Pulls up to `len` bytes from the beginning of the buffer and removes them.
 * Default `len` is the full buffer length.
 *
 * @function buffer:pull
 * @tparam[opt] int len Number of bytes to pull (default full length)
 * @treturn string Pulled data
 */
static int lua_buffer_pull(lua_State *L)
{
    struct eco_buffer *b = luaL_checkudata(L, 1, ECO_BUFFER_MT);
    int len = luaL_optinteger(L, 2, b->len);

    if (len < 0 || len > b->len)
        len = b->len;

    lua_pushlstring(L, (const char *)b->buf, len);
    eco_buffer_consume(b, len);

    return 1;
}

/**
 * Discard bytes from the start of the buffer.
 *
 * Removes up to `len` bytes from the start without returning them.
 * Returns the number of bytes actually discarded.
 *
 * @function buffer:discard
 * @tparam[opt] int len Number of bytes to discard (default full length)
 * @treturn int Number of bytes discarded
 */

static int lua_buffer_discard(lua_State *L)
{
    struct eco_buffer *b = luaL_checkudata(L, 1, ECO_BUFFER_MT);
    int len = luaL_optinteger(L, 2, b->len);

    if (len < 0 || len > b->len)
        len = b->len;

    eco_buffer_consume(b, len);

    lua_pushinteger(L, len);
    return 1;
}

/**
 * Get the total capacity of the buffer.
 *
 * @function buffer:size
 * @treturn int Total allocated size of the buffer in bytes
 */
static int lua_buffer_size(lua_State *L)
{
    struct eco_buffer *b = luaL_checkudata(L, 1, ECO_BUFFER_MT);
    lua_pushinteger(L, b->size);
    return 1;
}

/**
 * Get the current length of data in the buffer.
 *
 * @function buffer:len
 * @treturn int Number of bytes currently stored in the buffer
 */
static int lua_buffer_length(lua_State *L)
{
    struct eco_buffer *b = luaL_checkudata(L, 1, ECO_BUFFER_MT);
    lua_pushinteger(L, b->len);
    return 1;
}

/**
 * Clear the buffer contents.
 *
 * Resets the buffer length to zero. Data is not freed, buffer can be reused.
 *
 * @function buffer:clear
 * @treturn nil
 */
static int lua_buffer_clear(lua_State *L)
{
    struct eco_buffer *b = luaL_checkudata(L, 1, ECO_BUFFER_MT);
    b->len = 0;
    return 1;
}

/**
 * Find the first occurrence of a byte in the buffer starting from position.
 *
 * @function buffer:index
 * @tparam int pos Starting position (0-based)
 * @tparam string char Single character to search for
 * @treturn[1] int Index of the first occurrence
 * @treturn[2] nil If not found
 */
static int lua_buffer_index(lua_State *L)
{
    struct eco_buffer *b = luaL_checkudata(L, 1, ECO_BUFFER_MT);
    int pos = luaL_checkinteger(L, 2);
    const char *c = luaL_checkstring(L, 3);
    int i;

    if (pos < 0)
        pos = 0;

    if (pos > b->len)
        goto done;

    for (i = pos; i < b->len; i++) {
        if (b->buf[i] == *c) {
            lua_pushinteger(L, i);
            return 1;
        }
    }

done:
    lua_pushnil(L);
    return 1;
}

/**
 * Search for a substring in the buffer.
 *
 * @function buffer:find
 * @tparam int start Start position (0-based)
 * @tparam string pattern Substring to search
 * @treturn[1] int Index of the first occurrence
 * @treturn[2] nil If not found
 */
static int lua_buffer_find(lua_State *L)
{
    struct eco_buffer *b = luaL_checkudata(L, 1, ECO_BUFFER_MT);
    int start = luaL_checkinteger(L, 2);
    size_t needlelen;
    const char *needle = luaL_checklstring(L, 3, &needlelen);
    uint8_t *pos;

    if (start < 0)
        start = 0;

    if (start > b->len)
        goto done;

    pos = memmem(b->buf + start, b->len - start, needle, needlelen);
    if (pos) {
        lua_pushinteger(L, pos - b->buf);
        return 1;
    }

done:
    lua_pushnil(L);
    return 1;
}

/// @section end

static const struct luaL_Reg buffer_methods[] = {
    {"data", lua_buffer_data},
    {"pull", lua_buffer_pull},
    {"discard", lua_buffer_discard},
    {"size", lua_buffer_size},
    {"len", lua_buffer_length},
    {"clear", lua_buffer_clear},
    {"index", lua_buffer_index},
    {"find", lua_buffer_find},
    {NULL, NULL}
};

static int lua_eco_read2bk(lua_State *L, int status, lua_KContext ctx)
{
    struct eco_reader *rd = (struct eco_reader *)ctx;
    struct eco_buffer *b = rd->buf;
    int ret;

    if (rd->read) {
        struct eco_io *io = &rd->io;
        char *err = "";

        if (io->is_timeout) {
            io->is_timeout = 0;
            lua_pushnil(L);
            lua_pushliteral(L, "timeout");
            return 2;
        }

        ret = rd->read(b->buf + b->len, rd->expected, rd->ctx, &err);
        if (ret < 0) {
            if (ret == -EAGAIN) {
                io->co = L;
                return lua_yieldk(L, 0, (lua_KContext)io, lua_eco_read2bk);
            }

            lua_pushnil(L);
            lua_pushstring(L, err);
            epoll_ctl_io_del(L, io);
            return 2;
        }
        epoll_ctl_io_del(L, io);
    } else {
        ret = lua_io_readk(L, &rd->io, b->buf + b->len, rd->expected, lua_eco_read2bk);
        if (ret < 0)
            return 2;
    }

    if (ret == 0) {
        lua_pushnil(L);
        lua_pushliteral(L, "eof");
        return 2;
    }

    b->len += ret;
    lua_pushinteger(L, ret);
    return 1;
}

/**
 * reader object created by @{reader}.
 * @type reader
 */

/**
 * Read data into a buffer object.
 *
 * Reads up to `expected` bytes from the reader's file descriptor into
 * the given `eco.buffer` object. If the buffer cannot hold all data,
 * only the available space will be used.
 *
 * This method avoids repeated memory copies by using a pre-allocated buffer.
 *
 * @function reader:read2b
 * @tparam buffer b An @{eco.buffer} object
 * @tparam int expected Number of bytes expected to read (cannot be 0)
 * @tparam[opt] nnumber timeout Timeout in seconds (default nil = no timeout)
 * @treturn int bytes Number of bytes actually read
 * @treturn[2] nil On error or EOF
 * @treturn[2] string Error message or "eof"
 */

static int lua_eco_read2b(lua_State *L)
{
    struct eco_reader *rd = luaL_checkudata(L, 1, ECO_READER_MT);
    struct eco_buffer *b = luaL_checkudata(L, 2, ECO_BUFFER_MT);
    int expected = luaL_checkinteger(L, 3);
    double timeout = lua_tonumber(L, 4);
    size_t room = b->size - b->len;
    int ret;

    luaL_argcheck(L, expected != 0, 3, "expected size cannot be 0");

    if (rd->io.co)
        luaL_error(L, "another coroutine is already waiting for I/O on this file descriptor");

    if (room == 0) {
        lua_pushnil(L);
        lua_pushliteral(L, "buffer is full");
        return 2;
    }

    if (expected < 0 || expected > room)
        expected = room;

    rd->io.timeout = timeout;
    rd->expected = expected;
    rd->buf = b;

    if (rd->read) {
        char *err = "";
        ret = rd->read(b->buf + b->len, expected, rd->ctx, &err);
        if (ret < 0) {
            if (ret == -EAGAIN) {
                if (epoll_ctl_io_read(L, &rd->io) < 0) {
                    lua_pushnil(L);
                    lua_pushstring(L, strerror(errno));
                    return 2;
                }
                return lua_yieldk(L, 0, (lua_KContext)rd, lua_eco_read2bk);
            }
            lua_pushnil(L);
            lua_pushstring(L, err);
            return 2;
        }
    } else {
        ret = lua_io_read(L, &rd->io, b->buf + b->len, expected, lua_eco_read2bk);
        if (ret < 0)
            return 2;
    }

    if (ret == 0) {
        lua_pushnil(L);
        lua_pushliteral(L, "eof");
        return 2;
    }

    b->len += ret;
    lua_pushinteger(L, ret);
    return 1;
}

static int lua_eco_readk(lua_State *L, int status, lua_KContext ctx)
{
    struct eco_reader *rd = (struct eco_reader *)ctx;
    char *buf = rd->buf;
    int ret;

    ret = lua_io_readk(L, &rd->io, buf, rd->expected, lua_eco_readk);
    if (ret < 0) {
        free(buf);
        return 2;
    }

    if (ret == 0) {
        free(buf);
        lua_pushnil(L);
        lua_pushliteral(L, "eof");
        return 2;
    }

    lua_pushlstring(L, buf, ret);
    free(buf);

    return 1;
}

/**
 * Read data from the reader and return it as a Lua string.
 *
 * Reads up to `expected` bytes from the reader's file descriptor into a
 * temporary Lua string. Unlike `read2b`, this allocates memory for each read.
 *
 * @function reader:read
 * @tparam int expected Number of bytes to read (must be > 0)
 * @tparam[opt] double timeout Timeout in seconds (default nil = no timeout)
 * @treturn string Data read from the file descriptor
 * @treturn[2] nil On error or EOF
 * @treturn[2] string Error message or "eof"
 *
 * @usage
 * local data, err = reader:read(1024, 5)
 * if not data then print("Read failed:", err) end
 */
static int lua_eco_read(lua_State *L)
{
    struct eco_reader *rd = luaL_checkudata(L, 1, ECO_READER_MT);
    int expected = luaL_checkinteger(L, 2);
    double timeout = lua_tonumber(L, 3);
    char *buf;
    int ret;

    luaL_argcheck(L, expected > 0, 3, "expected size must be great than 0");

    if (rd->io.co)
        luaL_error(L, "another coroutine is already waiting for I/O on this file descriptor");

    buf = malloc(expected);
    if (!buf)
        return luaL_error(L, "no mem");

    rd->io.timeout = timeout;
    rd->expected = expected;
    rd->buf = buf;

    ret = lua_io_read(L, &rd->io, buf, expected, lua_eco_readk);
    if (ret < 0) {
        free(buf);
        return 2;
    }

    if (ret == 0) {
        free(buf);
        lua_pushnil(L);
        lua_pushliteral(L, "eof");
        return 2;
    }

    lua_pushlstring(L, buf, ret);
    free(buf);

    return 1;
}

/**
 * Cancel a pending read operation.
 *
 * If a coroutine is currently suspended in `read` or `read2b`, it will be
 * resumed immediately and return nil with error "canceled".
 *
 * @function reader:cancel
 * @treturn nil
 */
static int lua_eco_cancel(lua_State *L)
{
    struct eco_reader *rd = luaL_checkudata(L, 1, ECO_READER_MT);

    if (!rd->io.co)
        return 0;

    rd->io.is_canceled = 1;
    eco_resume_io(L, &rd->io);

    return 0;
}

/// @section end

static const struct luaL_Reg reader_methods[] = {
    {"read2b", lua_eco_read2b},
    {"read", lua_eco_read},
    {"cancel", lua_eco_cancel},
    {NULL, NULL}
};

static int lua_eco_writek(lua_State *L, int status, lua_KContext ctx)
{
    struct eco_writer *wr = (struct eco_writer *)ctx;
    int ret;

    if (wr->io.is_timeout) {
        wr->io.is_timeout = 0;
        luaL_unref(L, LUA_REGISTRYINDEX, wr->data.ref);
        lua_pushnil(L);
        lua_pushliteral(L, "timeout");
        return 2;
    }

    if (wr->write) {
        char *err = "";
        ret = wr->write(wr->data.data + wr->written, wr->total - wr->written, wr->ctx, &err);
        if (ret < 0) {
            if (ret == -EAGAIN) {
                ret = 0;
            } else {
                lua_pushnil(L);
                lua_pushstring(L, err);
                epoll_ctl_io_del(L, &wr->io);
                luaL_unref(L, LUA_REGISTRYINDEX, wr->data.ref);
                return 2;
            }
        }
    } else {
        ret = write(wr->io.fd, wr->data.data + wr->written, wr->total - wr->written);
        if (ret < 0)
            goto err;
    }

    wr->written += ret;

    if (wr->written < wr->total) {
        wr->io.co = L;
        return lua_yieldk(L, 0, (lua_KContext)wr, lua_eco_writek);
    }

    epoll_ctl_io_del(L, &wr->io);

    luaL_unref(L, LUA_REGISTRYINDEX, wr->data.ref);
    lua_pushinteger(L, wr->total);
    return 1;

err:
    lua_pushnil(L);
    lua_pushstring(L, strerror(errno));

    epoll_ctl_io_del(L, &wr->io);
    luaL_unref(L, LUA_REGISTRYINDEX, wr->data.ref);

    return 2;
}

/**
 * writer object created by @{writer}.
 * @type writer
 */

/**
 * Write data to the writer's file descriptor.
 *
 * Writes the given string `data` to the file descriptor wrapped by
 * this `eco.writer`. If the write would block, the coroutine is
 * suspended and resumed automatically when the descriptor is writable.
 *
 * @function writer:write
 * @tparam string data Data to write
 * @tparam[opt] number timeout Timeout in seconds (default nil = no timeout)
 * @treturn int Number of bytes written
 * @treturn[2] nil On error
 * @treturn[2] string Error message
 */
static int lua_eco_write(lua_State *L)
{
    struct eco_writer *wr = luaL_checkudata(L, 1, ECO_WRITER_MT);
    size_t size;
    const char *data = luaL_checklstring(L, 2, &size);
    double timeout = lua_tonumber(L, 3);
    int ret;

    if (wr->io.co)
        luaL_error(L, "another coroutine is already waiting for I/O on this file descriptor");

    if (wr->write) {
        char *err = "";
        ret = wr->write(data, size, wr->ctx, &err);
        if (ret < 0) {
            if (ret == -EAGAIN)
                goto again;
            lua_pushnil(L);
            lua_pushstring(L, err);
            return 2;
        }
    } else {
        ret = write(wr->io.fd, data, size);
        if (ret < 0) {
            if (errno == EAGAIN || errno == EWOULDBLOCK)
                goto again;
            goto err;
        }
    }

    if (ret < size)
        goto again;

    lua_pushinteger(L, size);
    return 1;

again:
    wr->io.timeout = timeout;

    if (epoll_ctl_io_write(L, &wr->io) < 0)
        goto err;

    lua_pushvalue(L, 2);
    wr->data.ref = luaL_ref(L, LUA_REGISTRYINDEX);
    wr->data.data = data;

    wr->total = size;
    wr->written = (ret > 0) ? ret : 0;

    return lua_yieldk(L, 0, (lua_KContext)wr, lua_eco_writek);

err:
    lua_pushnil(L);
    lua_pushstring(L, strerror(errno));
    return 2;
}

static int lua_eco_sendfilek(lua_State *L, int status, lua_KContext ctx)
{
    struct eco_writer *wr = (struct eco_writer *)ctx;
    int ret;

    if (wr->io.is_timeout) {
        wr->io.is_timeout = 0;
        close(wr->file.fd);
        lua_pushnil(L);
        lua_pushliteral(L, "timeout");
        return 2;
    }

    ret = sendfile(wr->io.fd, wr->file.fd, &wr->file.offset, wr->total - wr->written);
    if (ret < 0)
        goto err;

    wr->written += ret;

    if (wr->written < wr->total)
        return lua_yieldk(L, 0, (lua_KContext)wr, lua_eco_writek);

    epoll_ctl_io_del(L, &wr->io);

    close(wr->file.fd);
    lua_pushinteger(L, wr->total);
    return 1;

err:
    lua_pushnil(L);
    lua_pushstring(L, strerror(errno));

    epoll_ctl_io_del(L, &wr->io);
    close(wr->file.fd);

    return 2;
}

/**
 * Send a file's content to the writer's file descriptor.
 *
 * Uses the `sendfile` system call to send `len` bytes starting from
 * `offset` of the file at `path` to the writer's file descriptor.
 * If the operation would block, the coroutine is suspended and resumed
 * automatically when the descriptor is writable.
 *
 * @function writer:sendfile
 * @tparam string path Path to the file
 * @tparam int offset Offset in the file to start sending
 * @tparam int len Number of bytes to send
 * @tparam[opt] number timeout Timeout in seconds (default nil = no timeout)
 * @treturn int Number of bytes sent
 * @treturn[2] nil On error
 * @treturn[2] string Error message
 *
 * @usage
 * local wr = eco.writer(fd)
 * local n, err = wr:sendfile('/tmp/file.txt', 0, 1024)
 * if not n then print('Sendfile failed:', err) end
 */
static int lua_eco_sendfile(lua_State *L)
{
    struct eco_writer *wr = luaL_checkudata(L, 1, ECO_WRITER_MT);
    const char *path = luaL_checkstring(L, 2);
    off_t offset = luaL_checkinteger(L, 3);
    int len = luaL_checkinteger(L, 4);
    double timeout = lua_tonumber(L, 5);
    int ret, fd;

    if (wr->io.co)
        luaL_error(L, "another coroutine is already waiting for I/O on this file descriptor");

    fd = open(path, O_RDONLY);
    if (fd < 0) {
        lua_pushnil(L);
        lua_pushstring(L, strerror(errno));
        return 2;
    }

    ret = sendfile(wr->io.fd, fd, &offset, len);
    if (ret < 0) {
        if (errno == EAGAIN || errno == EWOULDBLOCK)
            goto again;
        goto err;
    }

    if (ret < len)
        goto again;

    close(fd);
    lua_pushinteger(L, len);
    return 1;

again:
    wr->io.timeout = timeout;

    if (epoll_ctl_io_write(L, &wr->io) < 0)
        goto err;

    wr->file.fd = fd;
    wr->file.offset = offset;

    wr->total = len;
    wr->written = (ret > 0) ? ret : 0;

    return lua_yieldk(L, 0, (lua_KContext)wr, lua_eco_sendfilek);

err:
    lua_pushnil(L);
    lua_pushstring(L, strerror(errno));
    close(fd);
    return 2;
}

/// @section end

static const struct luaL_Reg writer_methods[] = {
    {"write", lua_eco_write},
    {"sendfile", lua_eco_sendfile},
    {NULL, NULL}
};

static void eco_io_init(struct eco_io *io, int fd)
{
    memset(io, 0, sizeof(struct eco_io));

    io->fd = fd;
}

/**
 * Create a new async I/O object wrapping a file descriptor.
 *
 * This function sets the given file descriptor to non-blocking mode
 * and wraps it in an `eco.io` userdata object, allowing async I/O
 * operations via `io:wait()` and `io:cancel()`.
 *
 * @function io
 * @tparam int fd File descriptor to wrap.
 * @treturn io The new I/O object on success.
 * @treturn[2] nil On failure.
 * @treturn[2] string Error message.
 *
 * @usage
 * local io = eco.io(fd)
 * local ok, err = io:wait(eco.READ, 5)
 * if not ok then print('I/O wait failed:', err) end
 */
static int lua_eco_io(lua_State *L)
{
    int fd = luaL_checkinteger(L, 1);
    struct eco_io *io;

    if (set_fd_nonblock(fd) < 0)
        goto err;

    io = lua_newuserdata(L, sizeof(struct eco_io));
    eco_io_init(io, fd);
    luaL_setmetatable(L, ECO_IO_MT);
    return 1;

err:
    lua_pushnil(L);
    lua_pushstring(L, strerror(errno));
    return 2;
}

/**
 * Create a temporary buffer object for I/O operations.
 *
 * This function allocates a buffer object used as a temporary cache
 * for function `read2b`. It avoids repeated memory copying
 * when reading data from I/O sources.
 *
 * @function buffer
 * @tparam[opt] int size Size of the buffer in bytes (default 4096).
 * @treturn buffer Temporary buffer object.
 */
static int lua_eco_buffer(lua_State *L)
{
    int size = luaL_optinteger(L, 1, 4096);
    struct eco_buffer *b;

    luaL_argcheck(L, size > 0, 1, "size must be positive");

    b = lua_newuserdata(L, sizeof(struct eco_buffer) + size);
    b->size = size;
    b->len = 0;
    luaL_setmetatable(L, ECO_BUFFER_MT);

    return 1;
}

/**
 * Create a new reader object.
 *
 * Wraps a file descriptor in an `eco.reader` object for async I/O.
 * Optionally, a custom read function and context pointer can be provided.
 *
 * @function reader
 * @tparam int fd File descriptor to wrap
 * @tparam[opt] lightuserdata read Custom read function
 * @tparam[opt] lightuserdata ctx Context pointer for the read function
 * @treturn reader The reader object
 * @treturn[2] nil On failure
 * @treturn[2] string Error message
 *
 * @usage
 * local rd = eco.reader(fd)
 * local b = eco.buffer(4096)
 * 
 * local data, err = rd:read(1024)
 * print(data)
 *
 * local n, err = rd:read2b(b, 1024)
 * print(b:data())
 */
static int lua_eco_reader(lua_State *L)
{
    int fd = luaL_checkinteger(L, 1);
    int narg = lua_gettop(L);
    struct eco_reader *rd;

    if (narg > 1) {
        luaL_checktype(L, 2, LUA_TLIGHTUSERDATA);

        if (narg > 2)
            luaL_checktype(L, 3, LUA_TLIGHTUSERDATA);
    }

    if (set_fd_nonblock(fd) < 0)
        goto err;

    rd = lua_newuserdata(L, sizeof(struct eco_reader));
    eco_io_init(&rd->io, fd);

    rd->read = NULL;
    rd->ctx = NULL;

    if (narg > 1) {
        rd->read = lua_topointer(L, 2);

        if (narg > 2)
            rd->ctx = (void *)lua_topointer(L, 3);
    }

    luaL_setmetatable(L, ECO_READER_MT);
    return 1;

err:
    lua_pushnil(L);
    lua_pushstring(L, strerror(errno));
    return 2;
}

/**
 * Create a new writer object.
 *
 * Wraps a file descriptor in an `eco.writer` object for asynchronous
 * write operations. Optionally, a custom write function and context
 * pointer can be provided.
 *
 * @function eco.writer
 * @tparam int fd File descriptor to wrap
 * @tparam[opt] lightuserdata write Custom write function
 * @tparam[opt] lightuserdata ctx Context pointer for the write function
 * @treturn writer The writer object
 * @treturn[2] nil On failure
 * @treturn[2] string Error message
 *
 * @usage
 * local wr = eco.writer(fd)
 * wr:write('hello world')
 */
static int lua_eco_writer(lua_State *L)
{
    int fd = luaL_checkinteger(L, 1);
    int narg = lua_gettop(L);
    struct eco_writer *wr;

    if (narg > 1) {
        luaL_checktype(L, 2, LUA_TLIGHTUSERDATA);

        if (narg > 2)
            luaL_checktype(L, 3, LUA_TLIGHTUSERDATA);
    }

    if (set_fd_nonblock(fd) < 0)
        goto err;

    wr = lua_newuserdata(L, sizeof(struct eco_writer));
    eco_io_init(&wr->io, fd);

    wr->write = NULL;
    wr->ctx = NULL;

    if (narg > 1) {
        wr->write = lua_topointer(L, 2);

        if (narg > 2)
            wr->ctx = (void *)lua_topointer(L, 3);
    }

    luaL_setmetatable(L, ECO_WRITER_MT);
    return 1;

err:
    lua_pushnil(L);
    lua_pushstring(L, strerror(errno));
    return 2;
}

static int lua_eco_sleepk(lua_State *L, int status, lua_KContext ctx)
{
    struct eco_scheduler *sched = get_eco_scheduler(L);
    struct eco_timer *timer = (struct eco_timer *)ctx;

    eco_timer_free(sched, timer);

    return 0;
}

/**
 * Suspend the current coroutine for a given delay.
 *
 * This function yields the current Lua coroutine and resumes it
 * after `delay` seconds.
 *
 * @function sleep
 * @tparam number delay Number of seconds to sleep.
 * @treturn nil
 *
 * @usage
 * print('Sleeping for 1 second...')
 * eco.run(function()
 *     eco.sleep(1)
 *     print('Awake!')
 * end)
 */
static int lua_eco_sleep(lua_State *L)
{
    double delay = luaL_checknumber(L, 1);
    struct eco_scheduler *sched = get_eco_scheduler(L);
    struct eco_timer *timer = eco_timer_alloc(sched);

    if (!timer)
        return luaL_error(L, "failed to allocate timer");

    eco_timer_start(sched, L, timer, delay);

    return lua_yieldk(L, 0, (lua_KContext)timer, lua_eco_sleepk);
}

/**
 * Run a Lua function in a new coroutine.
 *
 * This function creates a new Lua coroutine, moves the provided function
 * and its arguments into it, and resumes the coroutine immediately.
 * The coroutine is tracked internally by `eco`.
 *
 * @function run
 * @tparam function func Function to run in the new coroutine.
 * @param ... Arguments to pass to the function.
 * @treturn thread The newly created coroutine.
 *
 * @usage
 * eco.run(function(a, b)
 *     print('Running in coroutine:v', a, b)
 *     eco.sleep(1)
 *     print('Done')
 * end, 10, 20)
 */
static int lua_eco_run(lua_State *L)
{
    int top = lua_gettop(L);
    lua_State *co;

    luaL_checktype(L, 1, LUA_TFUNCTION); /* func, a1, a2,... */

    co = lua_newthread(L);  /* func, a1, a2,..., co */

    lua_rotate(L, 1, 1);    /* co, func, a1, a2,... */
    lua_xmove(L, co, top);  /* co */

    set_obj(L, &eco_co_key, -1, co);

    eco_resume(L, co, top - 1);

    return 1;
}

/**
 * Resume a suspended coroutine.
 *
 * This function resumes a Lua coroutine previously yielded by
 * an `eco` asynchronous operation (like `eco.sleep` or `eco.io:wait`).
 *
 * @function resume
 * @tparam thread co Coroutine object to resume.
 * @treturn nil
 *
 * @usage
 * local co = coroutine.create(function()
 *     print('Start')
 *     eco.sleep(1)
 *     print('End')
 * end)
 *
 * eco.resume(co)
 */
static int lua_eco_resume(lua_State *L)
{
    lua_State *co = lua_tothread(L, 1);
    eco_resume(L, co, 0);
    return 0;
}

/**
 * Get the number of currently tracked coroutines.
 *
 * @function count
 * @treturn int Number of coroutines currently managed by `eco`.
 *
 * @usage
 * print('Active coroutines:', eco.count())
 */
static int lua_eco_count(lua_State *L)
{
    int count = 0;

    lua_rawgetp(L, LUA_REGISTRYINDEX, &eco_co_key);

    lua_pushnil(L);

    while (lua_next(L, -2) != 0) {
        count++;
        lua_pop(L, 1);
    }

    lua_pushinteger(L, count);
    return 1;
}

/**
 * Get a table of all currently tracked coroutines.
 *
 * @function all
 * @treturn table Table of Lua coroutine objects.
 *
 * @usage
 * local all_co = eco.all()
 * for i, co in ipairs(all_co) do
 *     print('Coroutinev', i, co)
 * end
 */
static int lua_eco_all(lua_State *L)
{
    int i = 1;

    lua_newtable(L);

    lua_rawgetp(L, LUA_REGISTRYINDEX, &eco_co_key);

    lua_pushnil(L);

    while (lua_next(L, -2) != 0)
        lua_rawseti(L, -4, i++);

    lua_pop(L, 1);

    return 1;
}

/**
 * Set a panic hook function for the scheduler.
 *
 * The provided function will be called when an uncaught error occurs
 * inside a coroutine managed by `eco`.
 *
 * @function set_panic_hook
 * @tparam function func Callback function to handle panic.
 * @treturn nil
 *
 * @usage
 * eco.set_panic_hook(function(...)
 *     for _, v in ipairs({...}) do
 *         print(v)
 *     end
 * end)
 */
static int lua_eco_set_panic_hook(lua_State *L)
{
    struct eco_scheduler *sched = get_eco_scheduler(L);

    if (lua_gettop(L) != 1)
        return luaL_error(L, "invalid argument");

    luaL_checktype(L, 1, LUA_TFUNCTION);

    sched->panic_hook = luaL_ref(L, LUA_REGISTRYINDEX);

    return 0;
}

static int get_next_timeout(struct eco_scheduler *sched, uint64_t now)
{
    struct eco_timer *timer;
    int64_t diff;

    if (list_empty(&sched->timers))
        return -1;

    timer = list_first_entry(&sched->timers, struct eco_timer, list);

    diff = timer->at - now;

    return diff > 0 ? diff : 0;
}

static void eco_process_timeouts(struct eco_scheduler *sched, lua_State *L, uint64_t now)
{
    struct eco_timer *timer;

    if (list_empty(&sched->timers))
        return;

    while (!list_empty(&sched->timers)) {
        timer = list_first_entry(&sched->timers, struct eco_timer, list);
        lua_State *co = timer->co;

        if (timer->at > now)
            break;

        if (co) {
            eco_resume(L, co, 0);
        } else {
            struct eco_io *io = container_of(timer, struct eco_io, timer);
            io->is_timeout = 1;
            epoll_ctl_io_del(L, io);
            eco_resume_io(L, io);
        }
    }
}

static void eco_process_io(lua_State *L, int nfds, struct epoll_event *events)
{
    for (int i = 0; i < nfds; i++) {
        struct eco_io *io = events[i].data.ptr;
        eco_resume_io(L, io);
    }
}

/**
 * Run the event loop of the eco scheduler.
 *
 * This function drives the scheduler, processing timers, I/O events,
 * and resuming coroutines as needed.
 *
 * @function loop
 * @treturn boolean true If the loop exits normally.
 * @treturn[2] nil On error.
 * @treturn[2] string Error message.
 */
static int lua_eco_loop(lua_State *L)
{
    struct eco_scheduler *sched = get_eco_scheduler(L);
    struct epoll_event events[MAX_EVENTS];
    int next_time;
    int nfds;

    while (!sched->quit) {
        uint64_t now = eco_time_now();

        eco_process_timeouts(sched, L, now);

        if (sched->quit)
            break;

        next_time = get_next_timeout(sched, now);

        nfds = epoll_wait(sched->epoll_fd, events, MAX_EVENTS, next_time);
        if (nfds < 0) {
            lua_pushnil(L);
            lua_pushstring(L, strerror(errno));
            return 2;
        }

        eco_process_io(L, nfds, events);
    }

    lua_pushboolean(L, true);

    return 1;
}

/**
 * Stop the eco scheduler main loop.
 *
 * Sets the scheduler's quit flag, causing a running `eco.loop` to exit
 * after the current iteration.
 *
 * @function unloop
 * @treturn nil
 *
 * @usage
 * -- Stop the event loop from another coroutine or signal handler
 * eco.unloop()
 */
static int lua_eco_unloop(lua_State *L)
{
    struct eco_scheduler *sched = get_eco_scheduler(L);
    sched->quit = true;
    return 0;
}

static int lua_eco_init(lua_State *L)
{
    struct eco_scheduler *sched = get_eco_scheduler(L);

    close(sched->epoll_fd);

    sched->epoll_fd = epoll_create1(0);
    if (sched->epoll_fd < 0)
        return luaL_error(L, "failed to create epoll: %s", strerror(errno));

    return 0;
}

static const struct luaL_Reg funcs[] = {
    {"io", lua_eco_io},
    {"buffer", lua_eco_buffer},
    {"reader", lua_eco_reader},
    {"writer", lua_eco_writer},
    {"sleep", lua_eco_sleep},
    {"run", lua_eco_run},
    {"resume", lua_eco_resume},
    {"count", lua_eco_count},
    {"all", lua_eco_all},
    {"set_panic_hook", lua_eco_set_panic_hook},
    {"loop", lua_eco_loop},
    {"unloop", lua_eco_unloop},
    {"init", lua_eco_init},
    {NULL, NULL}
};

int luaopen_eco_internal_eco(lua_State *L)
{
    creat_weak_table(L, "v", &eco_co_key);

    eco_scheduler_init(L);

    creat_metatable(L, ECO_IO_MT, NULL, io_methods);
    creat_metatable(L, ECO_BUFFER_MT, NULL, buffer_methods);
    creat_metatable(L, ECO_READER_MT, NULL, reader_methods);
    creat_metatable(L, ECO_WRITER_MT, NULL, writer_methods);

    luaL_newlib(L, funcs);

    lua_add_constant(L, "VERSION_MAJOR", ECO_VERSION_MAJOR);
    lua_add_constant(L, "VERSION_MINOR", ECO_VERSION_MINOR);
    lua_add_constant(L, "VERSION_PATCH", ECO_VERSION_PATCH);

    lua_pushliteral(L, ECO_VERSION_STRING);
    lua_setfield(L, -2, "VERSION");

    lua_add_constant(L, "READ", EPOLLIN);
    lua_add_constant(L, "WRITE", EPOLLOUT);

    return 1;
}
