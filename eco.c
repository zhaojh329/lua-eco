/* SPDX-License-Identifier: MIT */
/*
 * Author: Jianhui Zhao <zhaojh329@gmail.com>
 */

/**
 * Core runtime for lua-eco.
 *
 * This module implements the built-in event loop and cooperative coroutine
 * scheduler (epoll + timers). Most I/O in lua-eco is exposed as synchronous
 * looking Lua APIs, but is implemented using non-blocking file descriptors.
 * When an operation would block, the running coroutine yields and is resumed
 * automatically when the descriptor becomes ready.
 *
 * Exported constants:
 *
 * - `VERSION_MAJOR`, `VERSION_MINOR`, `VERSION_PATCH`: semantic version parts.
 * - `VERSION`: full version string.
 * - `READ`, `WRITE`: event flags for use with @{io:wait}.
 *
 * This module is built into the `eco` interpreter and is loaded
 * automatically into `_G.eco`. The interpreter also schedules user
 * scripts by creating a coroutine via `eco.run(...)` and starts the
 * scheduler with `eco.loop()` automatically.
 *
 * @module eco
 * @usage
 * #!/usr/bin/env eco
 *
 * local time = require 'eco.time'
 *
 * -- `eco` is injected into `_G` by the eco interpreter.
 *
 * eco.run(function(name)
 *     local co = coroutine.running()
 *     while true do
 *         print(time.now(), name, co)
 *         time.sleep(1.0)
 *     end
 * end, 'eco1')
 *
 * eco.run(function(name)
 *     local co = coroutine.running()
 *     while true do
 *         print(time.now(), name, co)
 *         time.sleep(2.0)
 *     end
 * end, 'eco2')
 */

#define _GNU_SOURCE

#include <sys/sendfile.h>
#include <sys/epoll.h>
#include <sys/wait.h>
#include <sys/time.h>
#include <sys/stat.h>
#include <stdbool.h>
#include <unistd.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <time.h>
#include <signal.h>

#include "config.h"
#include "eco.h"
#include "list.h"

static char eco_scheduler_key;
static char eco_co_key;

static volatile sig_atomic_t got_sigint;
static volatile sig_atomic_t got_sigchld;

#define MAX_EVENTS 128
#define MAX_TIMER_CACHE 32
#define RD_BUFSIZE 4096
#define FD_HASH_BUCKETS 256
#define IO_FAIRNESS_DURATION 300
#define CO_RUN_TIMEOUT 2000

#define ECO_IO_MT "struct eco_io *"
#define ECO_READER_MT "struct eco_reader *"
#define ECO_WRITER_MT "struct eco_writer *"

struct eco_scheduler {
    struct list_head timer_cache;
    struct list_head timers;
    struct list_head fds[FD_HASH_BUCKETS];
    size_t timer_cache_size;
    int panic_hook;
    int sigchld_hook;
    int epoll_fd;
    pid_t pid;
    uint32_t nfd;
    uint16_t co_run_timeout;
    uint64_t resumed_at;
    unsigned quit:1;
};

struct eco_timer {
    struct list_head list;
    uint64_t at;
    lua_State *co;
};

struct eco_fd {
    struct list_head list;
    struct eco_io *read_io;
    struct eco_io *write_io;
    int refcount;
    unsigned events:3;
    int fd;
};

struct eco_io {
    struct eco_fd *efd;
    struct eco_timer timer;
    unsigned is_timeout:1;
    unsigned is_canceled:1;
    unsigned fairness_yield:1;
    double timeout;
    lua_State *co;
};

static inline struct list_head *eco_fd_bucket(struct eco_scheduler *sched, int fd)
{
    return &sched->fds[(uint32_t)fd & (FD_HASH_BUCKETS - 1)];
}

struct eco_reader {
    struct eco_io io;
    luaL_Buffer b;
    char mode;
    union {
        size_t expected;
        struct {
            int needle_ref;
            const char *needle;
            size_t needle_len;
        };
    };
    int (*read)(void *buf, size_t len, void *ctx, char **err);
    void *ctx;
    size_t len;
    char buf[RD_BUFSIZE];
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

static uint64_t eco_time_now()
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
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
    struct eco_scheduler *sched = get_eco_scheduler(L);
    uint64_t duration;
    int nres, status;

    sched->resumed_at = eco_time_now();

    status = lua_resume(co, L, narg, &nres);

    duration = eco_time_now() - sched->resumed_at;

    if (sched->co_run_timeout > 0 && duration > sched->co_run_timeout) {
        lua_pushfstring(co,
                "coroutine execution timeout: run too long(%I ms) without yielding/dead (>%I ms)",
                duration, sched->co_run_timeout);
        status = LUA_ERRRUN;
    }

    switch (status) {
    case LUA_OK: /* dead */
        set_obj(L, &eco_co_key, 0, co);
        break;

    case LUA_YIELD:
        break;

    default:
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

static void eco_timer_stop(struct eco_timer *timer)
{
    if (!timer->at)
        return;

    timer->at = 0;
    timer->co = NULL;

    list_del(&timer->list);
}

static void eco_timer_start(struct eco_scheduler *sched, lua_State *L,
            struct eco_timer *timer, double seconds)
{
    const double max_seconds = UINT64_MAX / 1000.0;
    struct list_head *h = &sched->timers;
    struct eco_timer *pos;

    eco_timer_stop(timer);

    if (seconds > max_seconds)
        seconds = max_seconds;

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

static void *eco_new_fd_userdata(lua_State *L, int fd, size_t size, const char *mt)
{
    void *ud;

    if (set_fd_nonblock(fd) < 0)
        return NULL;

    ud = lua_newuserdatauv(L, size, 0);
    luaL_setmetatable(L, mt);

    memset(ud, 0, size);

    return ud;
}

/* Validate optional custom read/write callback arguments for reader/writer constructors. */
static void eco_check_custom_rw_callback_args(lua_State *L, int narg)
{
    if (narg <= 1)
        return;

    luaL_checktype(L, 2, LUA_TLIGHTUSERDATA);

    if (narg > 2)
        luaL_checktype(L, 3, LUA_TLIGHTUSERDATA);
}

static inline bool errno_wouldblock(void)
{
    return errno == EAGAIN || errno == EWOULDBLOCK;
}

static inline int push_nil_string(lua_State *L, const char *s)
{
    lua_pushnil(L);
    lua_pushstring(L, s);
    return 2;
}

static int push_nil_eof_or_closed(lua_State *L, int fd)
{
    const char *err;
    struct stat st;

    if (fstat(fd, &st) == 0 && S_ISSOCK(st.st_mode))
        err = "closed";
    else
        err = "eof";

    return push_nil_string(L, err);
}

static inline void eco_io_check_busy(lua_State *L, struct eco_io *io, int events)
{
    struct eco_fd *efd = io->efd;

    if (io->co)
        luaL_error(L, "another coroutine is already waiting on this I/O object");

    if ((events & EPOLLIN) && efd->read_io)
        luaL_error(L, "another coroutine is already waiting for read on this file descriptor");

    if ((events & EPOLLOUT) && efd->write_io)
        luaL_error(L, "another coroutine is already waiting for write on this file descriptor");
}

static int eco_fd_update_events(struct eco_scheduler *sched, struct eco_fd *efd)
{
    int events = (efd->read_io ? EPOLLIN : 0) | (efd->write_io ? EPOLLOUT : 0);
    struct epoll_event ev;
    int nfd = sched->nfd;
    int op, ret;

    if (events == efd->events)
        return 0;

    if (efd->events == 0) {
        op = EPOLL_CTL_ADD;
        nfd++;
    } else if (events == 0) {
        op = EPOLL_CTL_DEL;
        nfd--;
    } else {
        op = EPOLL_CTL_MOD;
    }

    ev.events = events | EPOLLERR | EPOLLHUP;
    ev.data.ptr = efd;

    ret = epoll_ctl(sched->epoll_fd, op, efd->fd, &ev);
    if (ret < 0)
        return -1;

    efd->events = events;
    sched->nfd = nfd;

    return 0;
}

static int eco_io_yieldk(lua_State *L, struct eco_io *io, int events, lua_KFunction k)
{
    struct eco_scheduler *sched = get_eco_scheduler(L);
    struct eco_fd *efd = io->efd;

    if (events & EPOLLIN)
        efd->read_io = io;

    if (events & EPOLLOUT)
        efd->write_io = io;

    if (eco_fd_update_events(sched, efd) < 0)
        return -1;

    io->co = L;

    if (io->timeout > 0)
        eco_timer_start(sched, NULL, &io->timer, io->timeout);

    return lua_yieldk(L, 0, (lua_KContext)io, k);
}

static void eco_io_fairness(lua_State *L, struct eco_io *io, lua_KFunction k)
{
    struct eco_scheduler *sched = get_eco_scheduler(L);

    if (eco_time_now() - sched->resumed_at < IO_FAIRNESS_DURATION)
        return;

    io->co = L;
    io->fairness_yield = true;

    eco_timer_start(sched, NULL, &io->timer, 0);

    lua_yieldk(L, 0, (lua_KContext)io, k);
}

static void eco_io_stop(lua_State *L, struct eco_io *io)
{
    struct eco_scheduler *sched = get_eco_scheduler(L);
    struct eco_fd *efd = io->efd;

    eco_timer_stop(&io->timer);

    if (efd->read_io == io)
        efd->read_io = NULL;

    if (efd->write_io == io)
        efd->write_io = NULL;

    eco_fd_update_events(sched, efd);

    io->co = NULL;
}

static struct eco_fd *eco_fd_get(lua_State *L, int fd)
{
    struct eco_scheduler *sched = get_eco_scheduler(L);
    struct list_head *bucket = eco_fd_bucket(sched, fd);
    struct eco_fd *efd;

    list_for_each_entry(efd, bucket, list) {
        if (efd->fd == fd) {
            efd->refcount++;
            return efd;
        }
    }

    efd = calloc(1, sizeof(struct eco_fd));
    if (!efd)
        return NULL;

    efd->fd = fd;
    efd->refcount++;

    list_add_tail(&efd->list, bucket);

    return efd;
}

static int eco_io_init(lua_State *L, struct eco_io *io, int fd)
{
    io->efd = eco_fd_get(L, fd);
    if (!io->efd)
        return luaL_error(L, "failed to allocate fd context");

    return 0;
}

static void eco_io_unbind_fd(lua_State *L, struct eco_io *io)
{
    struct eco_fd *efd = io->efd;

    if (!efd)
        return;

    if (io->co)
        eco_io_stop(L, io);

    efd->refcount--;

    if (efd->refcount == 0) {
        list_del(&efd->list);
        free(efd);
    }

    io->efd = NULL;
}

static int lua_io_gc(lua_State *L)
{
    struct eco_io *io = luaL_checkudata(L, 1, ECO_IO_MT);
    eco_io_unbind_fd(L, io);
    return 0;
}

static void sigint_handler(int signo)
{
    got_sigint = 1;
}

static void sigchld_handler(int signo)
{
    got_sigchld = 1;
}

static int install_signal_handler(int signo, void (*handler)(int), struct sigaction *oldact)
{
    struct sigaction sa = {};

    /* Keep SA_RESTART disabled so epoll_wait can be interrupted by signals. */
    sa.sa_flags = 0;

    sigemptyset(&sa.sa_mask);

    sa.sa_handler = handler;

    return sigaction(signo, &sa, oldact);
}

static void eco_push_wait_status(lua_State *L, int status)
{
    lua_newtable(L);

    if (WIFEXITED(status)) {
        lua_pushboolean(L, true);
        lua_setfield(L, -2, "exited");
        status = WEXITSTATUS(status);
    } else if (WIFSIGNALED(status)) {
        lua_pushboolean(L, true);
        lua_setfield(L, -2, "signaled");
        status = WTERMSIG(status);
    }

    lua_pushinteger(L, status);
    lua_setfield(L, -2, "status");
}

static void eco_process_sigchld(lua_State *L, struct eco_scheduler *sched)
{
    int status;
    pid_t pid;

    if (!got_sigchld)
        return;

    got_sigchld = 0;

    while (1) {
        pid = waitpid(-1, &status, WNOHANG | WUNTRACED);
        if (pid < 0) {
            if (errno == EINTR)
                continue;
            break;
        }

        if (pid == 0)
            break;

        if (sched->sigchld_hook == LUA_NOREF)
            continue;

        lua_rawgeti(L, LUA_REGISTRYINDEX, sched->sigchld_hook);
        lua_pushinteger(L, pid);
        eco_push_wait_status(L, status);
        lua_call(L, 2, 0);
    }
}

static int eco_set_callback_ref(lua_State *L, int idx, int *ref)
{
    luaL_unref(L, LUA_REGISTRYINDEX, *ref);
    *ref = LUA_NOREF;

    if (lua_isnoneornil(L, idx))
        return 0;

    luaL_checktype(L, idx, LUA_TFUNCTION);
    lua_pushvalue(L, idx);
    *ref = luaL_ref(L, LUA_REGISTRYINDEX);

    return 0;
}

static int eco_scheduler_init(lua_State *L)
{
    struct eco_scheduler *sched = calloc(1, sizeof(struct eco_scheduler));
    int i;

    if (!sched)
        return luaL_error(L, "failed to allocate scheduler");

    sched->epoll_fd = epoll_create1(0);
    if (sched->epoll_fd < 0)
        return luaL_error(L, "failed to create epoll: %s", strerror(errno));

    sched->panic_hook = LUA_NOREF;
    sched->sigchld_hook = LUA_NOREF;
    sched->pid = getpid();
    sched->quit = false;
    sched->resumed_at = 0;
    sched->co_run_timeout = CO_RUN_TIMEOUT;

    INIT_LIST_HEAD(&sched->timer_cache);
    INIT_LIST_HEAD(&sched->timers);
    for (i = 0; i < FD_HASH_BUCKETS; i++)
        INIT_LIST_HEAD(&sched->fds[i]);

    lua_pushlightuserdata(L, sched);
    lua_rawsetp(L, LUA_REGISTRYINDEX, &eco_scheduler_key);

    lua_newtable(L);
    lua_rawsetp(L, LUA_REGISTRYINDEX, &eco_co_key);

    return 0;
}

static int eco_io_push_wait_error(lua_State *L, struct eco_io *io)
{
    const char *err = NULL;

    if (io->is_timeout) {
        io->is_timeout = false;
        err = "timeout";
    } else if (io->is_canceled) {
        io->is_canceled = false;
        err = "canceled";
    }

    if (!err)
        return 0;

    return push_nil_string(L, err);
}

static int eco_io_waitk(lua_State *L, int status, lua_KContext ctx)
{
    struct eco_io *io = (struct eco_io *)ctx;
    int ret;

    ret = eco_io_push_wait_error(L, io);
    if (ret)
        return ret;

    eco_io_stop(L, io);
    lua_pushboolean(L, true);
    return 1;
}

static int eco_io_wait(lua_State *L, struct eco_io *io, int ev, double timeout)
{
    int ret;

    eco_io_check_busy(L, io, ev);

    io->timeout = timeout;

    ret = eco_io_yieldk(L, io, ev, eco_io_waitk);
    if (ret < 0) {
        push_errno(L, errno);
        eco_io_stop(L, io);
        return 2;
    }

    return ret;
}

/**
 * io handle returned by @{eco.io}.
 * @type io
 */

/**
 * Wait for the underlying file descriptor to become ready.
 *
 * Suspends the current coroutine until the file descriptor is ready
 * for reading (EPOLLIN) or writing (EPOLLOUT), or until an optional timeout.
 *
 * @function io:wait
 * @tparam integer ev Event mask: `eco.READ`, `eco.WRITE`, or a combination.
 * @tparam[opt] number timeout Timeout in seconds (default nil = no timeout).
 * @treturn boolean true If the underlying file descriptor to become ready.
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

    return eco_io_wait(L, io, ev, timeout);
}

static int eco_io_cancel(lua_State *L, struct eco_io *io)
{
    lua_State *co = io->co;
    if (!co)
        return 0;

    io->fairness_yield = false;
    io->is_canceled = true;

    eco_io_stop(L, io);
    eco_resume(L, co, 0);

    return 0;
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
    return eco_io_cancel(L, io);
}

/// @section end

static const struct luaL_Reg io_methods[] = {
    {"wait", lua_io_wait},
    {"cancel", lua_io_cancel},
    {NULL, NULL}
};

static const struct luaL_Reg io_metatable[] = {
    {"__gc", lua_io_gc},
    {"__close", lua_io_gc},
    {NULL, NULL}
};

/**
 * Create a new async I/O object wrapping a file descriptor.
 *
 * This function sets the given file descriptor to non-blocking mode
 * and wraps it in an `eco.io` userdata object, allowing async I/O
 * operations via `io:wait()` and `io:cancel()`.
 *
 * @function io
 * @tparam integer fd File descriptor to wrap.
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

    io = eco_new_fd_userdata(L, fd, sizeof(struct eco_io), ECO_IO_MT);
    if (!io)
        return push_errno(L, errno);

    eco_io_init(L, io, fd);

    return 1;
}

/**
 * reader object created by @{eco.reader}.
 * @type reader
 */

/**
 * Wait for the underlying file descriptor to become readable.
 *
 * @function reader:wait
 * @tparam[opt] number timeout Timeout in seconds (default nil = no timeout).
 * @treturn boolean true If the underlying file descriptor to become readable.
 * @treturn[2] nil On error.
 * @treturn[2] string Error message.
 */
static int lua_reader_wait(lua_State *L)
{
    struct eco_reader *rd = luaL_checkudata(L, 1, ECO_READER_MT);
    double timeout = lua_tonumber(L, 2);
    return eco_io_wait(L, &rd->io, EPOLLIN, timeout);
}

static bool eco_reader_find_line(const char *buf, size_t len, char mode,
                size_t *line_len, size_t *consumed, bool *strip_prev_tail_cr)
{
    size_t i;

    for (i = 0; i < len; i++) {
        if (buf[i] != '\n')
            continue;

        *line_len = (mode == 'l') ? i : (i + 1);
        *consumed = i + 1;
        if (strip_prev_tail_cr)
            *strip_prev_tail_cr = false;

        if (mode == 'l') {
            if (i > 0 && buf[i - 1] == '\r')
                (*line_len)--;
            else if (i == 0 && strip_prev_tail_cr)
                *strip_prev_tail_cr = true;
        }

        return true;
    }

    return false;
}

static void eco_reader_consume_buf(struct eco_reader *rd, size_t consumed, size_t total)
{
    if (consumed < total) {
        memmove(rd->buf, rd->buf + consumed, total - consumed);
        rd->len = total - consumed;
    } else {
        rd->len = 0;
    }
}

static void eco_reader_cleanup(lua_State *L, struct eco_reader *rd)
{
    if (rd->mode != 'u' || rd->needle_ref == LUA_NOREF)
        return;
    luaL_unref(L, LUA_REGISTRYINDEX, rd->needle_ref);
    rd->needle_ref = LUA_NOREF;
}

static inline int eco_reader_stop(lua_State *L, struct eco_reader *rd, int nret)
{
    eco_reader_cleanup(L, rd);
    eco_io_stop(L, &rd->io);
    return nret;
}

static int eco_reader_readuntil_consume(lua_State *L, struct eco_reader *rd)
{
    char *p;

    if (rd->len < rd->needle_len)
        return 0;

    p = memmem(rd->buf, rd->len, rd->needle, rd->needle_len);
    if (p) {
        size_t matched = p - rd->buf;

        lua_pushlstring(L, rd->buf, matched);
        eco_reader_consume_buf(rd, matched + rd->needle_len, rd->len);
        lua_pushboolean(L, true);
        eco_reader_cleanup(L, rd);
        return 2;
    }

    if (rd->len > rd->needle_len) {
        size_t out_len = rd->len - rd->needle_len + 1;

        lua_pushlstring(L, rd->buf, out_len);
        eco_reader_consume_buf(rd, out_len, rd->len);
        eco_reader_cleanup(L, rd);
        return 1;
    }

    return 0;
}

static int eco_reader_read_once(lua_State *L, struct eco_reader *rd,
            lua_KFunction k, bool continuation)
{
    struct eco_io *io = &rd->io;
    char mode = rd->mode;
    int ret;

    if (continuation) {
        ret = eco_io_push_wait_error(L, io);
        if (ret)
            goto unref;
    }

    while (1) {
        size_t size;
        char *buf;

        eco_io_fairness(L, io, k);

        if (mode == 'a')
            size = LUAL_BUFFERSIZE;
        else if (mode == 'u')
            size = RD_BUFSIZE - rd->len;
        else if (mode == 'l' || mode == 'L')
            size = RD_BUFSIZE;
        else /* any or full */
            size = rd->expected;

        if (mode == 'f' || mode == 'a' || mode == 0)
            buf = luaL_prepbuffsize(&rd->b, size);
        else if (mode == 'u')
            buf = rd->buf + rd->len;
        else
            buf = rd->buf;

        if (rd->read) {
            char *err = "";

            ret = rd->read(buf, size, rd->ctx, &err);
            if (ret < 0) {
                if (ret == -EAGAIN) {
                    ret = eco_io_yieldk(L, io, EPOLLIN, k);
                    if (ret < 0)
                        goto err;
                    return ret;
                }

                push_nil_string(L, err);
                goto unref;
            }
        } else {
            ret = read(io->efd->fd, buf, size);
            if (ret < 0) {
                if (errno_wouldblock()) {
                    ret = eco_io_yieldk(L, io, EPOLLIN, k);
                    if (ret < 0)
                        goto err;
                    return ret;
                }
                goto err;
            }
        }

        if (ret == 0) {
            if (mode == 'u') {
                if (rd->len > 0) {
                    lua_pushlstring(L, rd->buf, rd->len);
                    rd->len = 0;
                    return eco_reader_stop(L, rd, 1);
                }

                push_nil_eof_or_closed(L, io->efd->fd);
                goto unref;
            }

            if (mode == 'a') {
                if (continuation || luaL_bufflen(&rd->b) > 0) {
                    luaL_pushresult(&rd->b);
                    return eco_reader_stop(L, rd, 1);
                }
            }

            push_nil_eof_or_closed(L, io->efd->fd);
            goto unref;
        }

        if (mode == 'f' || mode == 0) {
            luaL_addsize(&rd->b, ret);

            if (mode == 'f') {
                rd->expected -= ret;
                if (rd->expected > 0)
                    continue;
            }

            luaL_pushresult(&rd->b);
            return eco_reader_stop(L, rd, 1);
        }

        if (mode == 'a') {
            luaL_addsize(&rd->b, ret);
            continue;
        }

        if (mode == 'u') {
            rd->len += ret;

            ret = eco_reader_readuntil_consume(L, rd);
            if (ret)
                return eco_reader_stop(L, rd, ret);

            continue;
        }

        {
            size_t line_len, consumed;
            bool strip_prev_tail_cr;

            if (eco_reader_find_line(buf, ret, mode, &line_len, &consumed, &strip_prev_tail_cr)) {
                luaL_addlstring(&rd->b, buf, line_len);
                eco_reader_consume_buf(rd, consumed, ret);
                luaL_pushresult(&rd->b);

                if (mode == 'l' && strip_prev_tail_cr) {
                    size_t len;
                    const char *line = lua_tolstring(L, -1, &len);

                    if (len > 0 && line[len - 1] == '\r') {
                        lua_pushlstring(L, line, len - 1);
                        lua_replace(L, -2);
                    }
                }

                return eco_reader_stop(L, rd, 1);
            }
        }

        luaL_addlstring(&rd->b, buf, ret);
    }

err:
    push_errno(L, errno);
unref:
    return eco_reader_stop(L, rd, 2);
}

static int lua_reader_readk(lua_State *L, int status, lua_KContext ctx)
{
    struct eco_reader *rd = (struct eco_reader *)ctx;
    return eco_reader_read_once(L, rd, lua_reader_readk, true);
}

/**
 * Reads data from the underlying file descriptor in the given format.
 *
 * The available formats are:
 *
 * - `"a"`: reads the whole file or reads from socket until the connection closed.
 * - `"l"`: reads the next line skipping the end of line(The line is terminated by a
 * Line Feed (LF) character (ASCII 10), optionally preceded by a Carriage
 * Return (CR) character (ASCII 13). The CR and LF characters are not included
 * in the returned line).
 * - `"L"`: reads the next line keeping the end-of-line character.
 * - `int`: reads a string with up to this number of bytes.
 *
 * @function reader:read
 * @tparam int|string format
 * @tparam[opt] number timeout Timeout in seconds (default nil = no timeout)
 * @treturn string Data read from the file descriptor
 * @treturn[2] nil On error or EOF
 * @treturn[2] string Error message, "eof" or "closed"
 *
 * @usage
 * local data, err = reader:read(1024, 5)
 * if not data then print("Read failed:", err) end
 */
static int lua_reader_read(lua_State *L)
{
    struct eco_reader *rd = luaL_checkudata(L, 1, ECO_READER_MT);
    double timeout = lua_tonumber(L, 3);
    const char *mode = "";
    int expected = 0;

    eco_io_check_busy(L, &rd->io, EPOLLIN);

    if (lua_isinteger(L, 2)) {
        expected = lua_tointeger(L, 2);
        luaL_argcheck(L, expected > 0, 2, "expected size must be greater than 0");

        if (rd->len > 0) {
            if (expected > rd->len)
                expected = rd->len;
            lua_pushlstring(L, rd->buf, expected);
            eco_reader_consume_buf(rd, expected, rd->len);
            return 1;
        }
    } else if (lua_isstring(L, 2)) {
        size_t len;
        mode = lua_tolstring(L, 2, &len);

        if (*mode == '*') {
            mode++;
            len--;
        }

        if (len != 1)
            return luaL_argerror(L, 2, "invalid format");

        if (*mode != 'l' && *mode != 'L' && *mode != 'a')
            return luaL_argerror(L, 2, "invalid format");
    } else {
        return luaL_argerror(L, 2, "invalid format");
    }

    if ((*mode == 'l' || *mode == 'L') && rd->len > 0) {
        size_t line_len, consumed;

        if (eco_reader_find_line(rd->buf, rd->len, *mode,
                &line_len, &consumed, NULL)) {
            lua_pushlstring(L, rd->buf, line_len);
            eco_reader_consume_buf(rd, consumed, rd->len);

            return 1;
        }
    }

    rd->io.timeout = timeout;
    rd->expected = expected;
    rd->mode = *mode;

    luaL_buffinit(L, &rd->b);
    luaL_addlstring(&rd->b, rd->buf, rd->len);
    rd->len = 0;

    return eco_reader_read_once(L, rd, lua_reader_readk, false);
}

/**
 * Reads exactly `size` bytes from the underlying file descriptor.
 *
 * This method will not return until it reads exactly this size of data or an error occurs.
 *
 * @function reader:readfull
 * @tparam integer size
 * @tparam[opt] number timeout Timeout in seconds (default nil = no timeout)
 * @treturn string Data read from the file descriptor
 * @treturn[2] nil On error or EOF
 * @treturn[2] string Error message, "eof" or "closed"
 */
static int lua_reader_readfull(lua_State *L)
{
    struct eco_reader *rd = luaL_checkudata(L, 1, ECO_READER_MT);
    int size = luaL_checkinteger(L, 2);
    double timeout = lua_tonumber(L, 3);

    luaL_argcheck(L, size > 0, 2, "size must be greater than 0");

    eco_io_check_busy(L, &rd->io, EPOLLIN);

    if (rd->len >= size) {
        lua_pushlstring(L, rd->buf, size);
        eco_reader_consume_buf(rd, size, rd->len);
        return 1;
    }

    rd->io.timeout = timeout;
    rd->expected = size - rd->len;
    rd->mode = 'f';

    luaL_buffinit(L, &rd->b);
    luaL_addlstring(&rd->b, rd->buf, rd->len);
    rd->len = 0;

    return eco_reader_read_once(L, rd, lua_reader_readk, false);
}

static int lua_reader_readuntilk(lua_State *L, int status, lua_KContext ctx)
{
    struct eco_reader *rd = (struct eco_reader *)ctx;
    return eco_reader_read_once(L, rd, lua_reader_readuntilk, true);
}

/**
 * Read until the specified `needle` is found.
 *
 * This function can be called multiple times. It returns data as it arrives.
 * When `needle` is seen, it returns the data preceding it and a boolean `true`.
 * The `needle` itself is consumed and not included in returned data.
 *
 * @function reader:readuntil
 * @tparam string needle Non-empty delimiter.
 * @tparam[opt] number timeout Timeout in seconds (default nil = no timeout)
 * @treturn string Data read from the file descriptor
 * @treturn[opt] boolean true when delimiter is found.
 * @treturn[2] nil On error or EOF
 * @treturn[2] string Error message, "eof" or "closed"
 */
static int lua_reader_readuntil(lua_State *L)
{
    struct eco_reader *rd = luaL_checkudata(L, 1, ECO_READER_MT);
    size_t needle_len;
    const char *needle = luaL_checklstring(L, 2, &needle_len);
    double timeout = lua_tonumber(L, 3);
    int ret;

    luaL_argcheck(L, needle_len > 0 && needle_len <= 256, 2,
                  "needle length must be 1~256 bytes");

    eco_io_check_busy(L, &rd->io, EPOLLIN);

    rd->io.timeout = timeout;
    rd->mode = 'u';
    rd->needle = needle;
    rd->needle_len = needle_len;
    rd->needle_ref = LUA_NOREF;

    ret = eco_reader_readuntil_consume(L, rd);
    if (ret)
        return ret;

    lua_pushvalue(L, 2);
    rd->needle_ref = luaL_ref(L, LUA_REGISTRYINDEX);

    return eco_reader_read_once(L, rd, lua_reader_readuntilk, false);
}

/**
 * Cancel a pending read operation.
 *
 * If a coroutine is currently suspended in `read`, `read2b` or `wait`, it will be
 * resumed immediately and return nil with error "canceled".
 *
 * @function reader:cancel
 * @treturn nil
 */
static int lua_reader_cancel(lua_State *L)
{
    struct eco_reader *rd = luaL_checkudata(L, 1, ECO_READER_MT);
    return eco_io_cancel(L, &rd->io);
}

/// @section end

static const struct luaL_Reg reader_methods[] = {
    {"wait", lua_reader_wait},
    {"read", lua_reader_read},
    {"readfull", lua_reader_readfull},
    {"readuntil", lua_reader_readuntil},
    {"cancel", lua_reader_cancel},
    {NULL, NULL}
};

static int lua_reader_gc(lua_State *L)
{
    struct eco_reader *rd = luaL_checkudata(L, 1, ECO_READER_MT);
    eco_reader_cleanup(L, rd);
    eco_io_unbind_fd(L, &rd->io);
    return 0;
}

static const struct luaL_Reg reader_metatable[] = {
    {"__gc", lua_reader_gc},
    {"__close", lua_reader_gc},
    {NULL, NULL}
};

/**
 * Create a new reader object.
 *
 * Wraps a file descriptor in an `eco.reader` object for async I/O.
 * Optionally, a custom read function and context pointer can be provided.
 *
 * @function reader
 * @tparam integer fd File descriptor to wrap
 * @tparam[opt] lightuserdata read Custom read function
 * @tparam[opt] lightuserdata ctx Context pointer for the read function
 * @treturn reader The reader object
 * @treturn[2] nil On failure
 * @treturn[2] string Error message
 *
 * @usage
 * local rd = eco.reader(fd)
 * local line, err = rd:read('l')
 * if not line then
 *     print('read fail:', err)
 *     return
 * end
 * print(line)
 */
static int lua_eco_reader(lua_State *L)
{
    int fd = luaL_checkinteger(L, 1);
    int narg = lua_gettop(L);
    struct eco_reader *rd;

    eco_check_custom_rw_callback_args(L, narg);

    rd = eco_new_fd_userdata(L, fd, sizeof(struct eco_reader), ECO_READER_MT);
    if (!rd)
        return push_errno(L, errno);

    rd->needle_ref = LUA_NOREF;

    eco_io_init(L, &rd->io, fd);

    if (narg > 1) {
        rd->read = lua_topointer(L, 2);

        if (narg > 2)
            rd->ctx = (void *)lua_topointer(L, 3);
    }

    return 1;
}


/**
 * writer object created by @{eco.writer}.
 * @type writer
 */

/**
 * Wait for the underlying file descriptor to become writable.
 *
 * @function writer:wait
 * @tparam[opt] number timeout Timeout in seconds (default nil = no timeout).
 * @treturn boolean true If the underlying file descriptor to become writable.
 * @treturn[2] nil On error.
 * @treturn[2] string Error message.
 */
static int lua_writer_wait(lua_State *L)
{
    struct eco_writer *wr = luaL_checkudata(L, 1, ECO_WRITER_MT);
    double timeout = lua_tonumber(L, 2);
    return eco_io_wait(L, &wr->io, EPOLLOUT, timeout);
}

static int eco_write_once(lua_State *L, struct eco_writer *wr,
            lua_KFunction k, bool continuation)
{
    struct eco_io *io = &wr->io;
    int ret;

    if (continuation) {
        ret = eco_io_push_wait_error(L, io);
        if (ret)
            goto unref;
    }

    if (!continuation)
        eco_io_fairness(L, io, k);

    if (wr->write) {
        char *err = "";
        ret = wr->write(wr->data.data + wr->written, wr->total - wr->written, wr->ctx, &err);
        if (ret < 0) {
            if (ret == -EAGAIN) {
                ret = 0;
            } else {
                push_nil_string(L, err);
                goto unref;
            }
        }
    } else {
        ret = write(io->efd->fd, wr->data.data + wr->written, wr->total - wr->written);
        if (ret < 0) {
            if (errno_wouldblock())
                ret = 0;
            else
                goto err;
        }
    }

    wr->written += ret;

    if (wr->written < wr->total) {
        ret = eco_io_yieldk(L, io, EPOLLOUT, k);
        if (ret < 0)
            goto err;
        return ret;
    }

    luaL_unref(L, LUA_REGISTRYINDEX, wr->data.ref);
    lua_pushinteger(L, wr->total);
    eco_io_stop(L, io);
    return 1;

err:
    push_errno(L, errno);
unref:
    luaL_unref(L, LUA_REGISTRYINDEX, wr->data.ref);
    eco_io_stop(L, io);
    return 2;
}

static int lua_writer_writek(lua_State *L, int status, lua_KContext ctx)
{
    struct eco_writer *wr = (struct eco_writer *)ctx;
    return eco_write_once(L, wr, lua_writer_writek, true);
}

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
 * @treturn integer Number of bytes written
 * @treturn[2] nil On error
 * @treturn[2] string Error message
 */
static int lua_writer_write(lua_State *L)
{
    struct eco_writer *wr = luaL_checkudata(L, 1, ECO_WRITER_MT);
    size_t size;
    const char *data = luaL_checklstring(L, 2, &size);
    double timeout = lua_tonumber(L, 3);

    eco_io_check_busy(L, &wr->io, EPOLLOUT);

    wr->io.timeout = timeout;
    wr->total = size;
    wr->written = 0;

    lua_pushvalue(L, 2);
    wr->data.ref = luaL_ref(L, LUA_REGISTRYINDEX);
    wr->data.data = data;

    return eco_write_once(L, wr, lua_writer_writek, false);
}

static int lua_writer_sendfilek(lua_State *L, int status, lua_KContext ctx)
{
    struct eco_writer *wr = (struct eco_writer *)ctx;
    struct eco_io *io = &wr->io;
    int ret;

    ret = eco_io_push_wait_error(L, io);
    if (ret)
        goto out_close;

    ret = sendfile(io->efd->fd, wr->file.fd, &wr->file.offset, wr->total - wr->written);
    if (ret < 0) {
        if (errno_wouldblock())
            goto wait_writable;
        goto err;
    }

    if (ret == 0) {
        push_nil_eof_or_closed(L, io->efd->fd);
        ret = 2;
        goto out_close;
    }

    wr->written += ret;

    if (wr->written < wr->total) {
wait_writable:
        ret = eco_io_yieldk(L, io, EPOLLOUT, lua_writer_sendfilek);
        if (ret < 0)
            goto err;
        return ret;
    }

    lua_pushinteger(L, wr->total);
    ret = 1;
    goto out_close;

err:
    push_errno(L, errno);
    ret = 2;

out_close:
    close(wr->file.fd);
    eco_io_stop(L, io);
    return ret;
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
 * @tparam integer offset Offset in the file to start sending
 * @tparam integer len Number of bytes to send
 * @tparam[opt] number timeout Timeout in seconds (default nil = no timeout)
 * @treturn integer Number of bytes sent
 * @treturn[2] nil On error
 * @treturn[2] string Error message, "eof" or "closed"
 *
 * @usage
 * local wr = eco.writer(fd)
 * local n, err = wr:sendfile('/tmp/file.txt', 0, 1024)
 * if not n then print('Sendfile failed:', err) end
 */
static int lua_writer_sendfile(lua_State *L)
{
    struct eco_writer *wr = luaL_checkudata(L, 1, ECO_WRITER_MT);
    const char *path = luaL_checkstring(L, 2);
    off_t offset = luaL_checkinteger(L, 3);
    int len = luaL_checkinteger(L, 4);
    double timeout = lua_tonumber(L, 5);
    struct eco_io *io = &wr->io;
    int ret = 0, fd;

    luaL_argcheck(L, offset >= 0, 3, "offset must be greater than or equal to 0");
    luaL_argcheck(L, len > 0, 4, "len must be great than 0");

    eco_io_check_busy(L, &wr->io, EPOLLOUT);

    fd = open(path, O_RDONLY);
    if (fd < 0)
        return push_errno(L, errno);

    wr->io.timeout = timeout;
    wr->file.fd = fd;
    wr->file.offset = offset;
    wr->total = len;
    wr->written = 0;

    eco_io_fairness(L, io, lua_writer_sendfilek);

    ret = sendfile(wr->io.efd->fd, fd, &offset, len);
    if (ret < 0) {
        if (errno_wouldblock())
            goto again;
        goto err;
    }

    if (ret == 0) {
        push_nil_eof_or_closed(L, wr->io.efd->fd);
        ret = 2;
        goto out_close;
    }

    if (ret < len)
        goto again;

    lua_pushinteger(L, len);
    ret = 1;
    goto out_close;

again:
    wr->file.offset = offset;
    wr->written = (ret > 0) ? ret : 0;

    ret = eco_io_yieldk(L, &wr->io, EPOLLOUT, lua_writer_sendfilek);
    if (ret < 0)
        goto err;
    return ret;

err:
    push_errno(L, errno);
    ret = 2;
    eco_io_stop(L, &wr->io);

out_close:
    close(fd);
    return ret;
}

/**
 * Cancel a pending write operation.
 *
 * If a coroutine is currently suspended in `write`, `sendfile` or `wait`, it will be
 * resumed immediately and return nil with error "canceled".
 *
 * @function writer:cancel
 * @treturn nil
 */
static int lua_writer_cancel(lua_State *L)
{
    struct eco_writer *wr = luaL_checkudata(L, 1, ECO_WRITER_MT);
    return eco_io_cancel(L, &wr->io);
}

/// @section end

static const struct luaL_Reg writer_methods[] = {
    {"wait", lua_writer_wait},
    {"write", lua_writer_write},
    {"sendfile", lua_writer_sendfile},
    {"cancel", lua_writer_cancel},
    {NULL, NULL}
};

static int lua_writer_gc(lua_State *L)
{
    struct eco_writer *wr = luaL_checkudata(L, 1, ECO_WRITER_MT);
    eco_io_unbind_fd(L, &wr->io);
    return 0;
}

static const struct luaL_Reg writer_metatable[] = {
    {"__gc", lua_writer_gc},
    {"__close", lua_writer_gc},
    {NULL, NULL}
};

/**
 * Create a new writer object.
 *
 * Wraps a file descriptor in an `eco.writer` object for asynchronous
 * write operations. Optionally, a custom write function and context
 * pointer can be provided.
 *
 * @function eco.writer
 * @tparam integer fd File descriptor to wrap
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

    eco_check_custom_rw_callback_args(L, narg);

    wr = eco_new_fd_userdata(L, fd, sizeof(struct eco_writer), ECO_WRITER_MT);
    if (!wr)
        return push_errno(L, errno);

    eco_io_init(L, &wr->io, fd);

    if (narg > 1) {
        wr->write = lua_topointer(L, 2);

        if (narg > 2)
            wr->ctx = (void *)lua_topointer(L, 3);
    }

    return 1;
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
    struct eco_scheduler *sched = get_eco_scheduler(L);
    double delay = luaL_checknumber(L, 1);
    struct eco_timer *timer;

    luaL_argcheck(L, delay >= 0, 1, "delay must be greater than or equal to 0");

    timer = eco_timer_alloc(sched);
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

static int lua_eco_resume(lua_State *L)
{
    lua_State *co;

    luaL_checktype(L, 1, LUA_TTHREAD);

    co = lua_tothread(L, 1);
    eco_resume(L, co, 0);

    return 0;
}

/**
 * Get the number of currently tracked coroutines.
 *
 * @function count
 * @treturn integer Number of coroutines currently managed by `eco`.
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
 * for i, co in ipairs(eco.all()) do
 *     print('Coroutine', i, co)
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
 * Set or clear the scheduler panic hook.
 *
 * The hook is called when an uncaught error occurs inside a coroutine
 * managed by `eco`.
 *
 * The callback receives two traceback strings:
 *
 * 1. traceback from the currently running coroutine (the one that failed)
 * 2. traceback from the coroutine/context that resumed it
 *
 * Pass `nil` to clear a previously installed hook.
 *
 * @function set_panic_hook
 * @tparam[opt] function func Panic callback `func(traceback1, traceback2)`.
 *
 * @usage
 * eco.set_panic_hook(function(traceback1, traceback2)
 *     print(traceback1)
 *     print(traceback2)
 * end)
 *
 * -- clear hook
 * eco.set_panic_hook(nil)
 */
static int lua_eco_set_panic_hook(lua_State *L)
{
    struct eco_scheduler *sched = get_eco_scheduler(L);
    return eco_set_callback_ref(L, 1, &sched->panic_hook);
}

/**
 * Set or clear coroutine resume watchdog timeout in milliseconds.
 *
 * If a single `resume` runs longer than this timeout, eco triggers panic
 * and prints traceback via the existing panic path.
 *
 * The default timeout is 2000 milliseconds.
 *
 * @function set_watchdog_timeout
 * @tparam integer ms Timeout in milliseconds, `0` means disabled.
 */
static int lua_eco_set_watchdog_timeout(lua_State *L)
{
    struct eco_scheduler *sched = get_eco_scheduler(L);
    lua_Integer timeout_ms = luaL_checkinteger(L, 1);

    luaL_argcheck(L, timeout_ms >= 0 && timeout_ms <= 5000,
              1, "timeout must be in range [0, 5000]");

    sched->co_run_timeout = timeout_ms;

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

static void eco_resume_io(lua_State *L, struct eco_io *io)
{
    lua_State *co = io->co;
    io->fairness_yield = false;
    eco_resume(L, co, 0);
}

static void eco_process_timeouts(struct eco_scheduler *sched, lua_State *L, uint64_t now)
{
    struct eco_timer *timer;

    while (!list_empty(&sched->timers)) {
        timer = list_first_entry(&sched->timers, struct eco_timer, list);
        lua_State *co = timer->co;

        if (timer->at > now)
            break;

        if (co) {
            eco_timer_stop(timer);
            eco_resume(L, co, 0);
        } else {
            struct eco_io *io = container_of(timer, struct eco_io, timer);

            co = io->co;

            if (io->fairness_yield) {
                eco_timer_stop(timer);
            } else {
                io->is_timeout = true;
                eco_io_stop(L, io);
            }

            io->fairness_yield = false;
            eco_resume(L, co, 0);
        }
    }
}

static void eco_process_io(lua_State *L, int nfds, struct epoll_event *events)
{
    for (int i = 0; i < nfds; i++) {
        struct eco_fd *efd = events[i].data.ptr;
        int ev = events[i].events;
        struct eco_io *read_io = NULL;
        struct eco_io *write_io = NULL;

        if ((ev & (EPOLLIN | EPOLLERR | EPOLLHUP)) && efd->read_io)
            read_io = efd->read_io;

        if ((ev & (EPOLLOUT | EPOLLERR | EPOLLHUP)) && efd->write_io)
            write_io = efd->write_io;

        if (!read_io && !write_io)
            continue;

        if (read_io == write_io) {
            eco_resume_io(L, read_io);
            continue;
        }

        if (read_io)
            eco_resume_io(L, read_io);

        if (write_io)
            eco_resume_io(L, write_io);
    }
}

/**
 * Run the event loop of the eco scheduler.
 *
 * This function drives the scheduler, processing timers, I/O events,
 * and resuming coroutines as needed. `eco.loop()` returns when `eco.unloop()`
 * is called, when interrupted by SIGINT, or when there are no monitorable
 * events left (no pending I/O watchers and no scheduled timers).
 *
 * @function loop
 * @treturn nil If the loop exits normally
 * @treturn[2] string Error message.
 */
static int lua_eco_loop(lua_State *L)
{
    struct eco_scheduler *sched = get_eco_scheduler(L);
    struct epoll_event events[MAX_EVENTS];
    struct sigaction old_sigpipe;
    struct sigaction old_sigint;
    struct sigaction old_sigchld;
    bool sigpipe_installed = false;
    bool sigint_installed = false;
    bool sigchld_installed = false;
    int err = 0;

    sched->quit = false;

    got_sigint = 0;
    got_sigchld = 0;

    if (install_signal_handler(SIGPIPE, SIG_IGN, &old_sigpipe) < 0) {
        err = errno;
        goto out;
    }
    sigpipe_installed = true;

    if (install_signal_handler(SIGINT, sigint_handler, &old_sigint) < 0) {
        err = errno;
        goto out;
    }
    sigint_installed = true;

    if (install_signal_handler(SIGCHLD, sigchld_handler, &old_sigchld) < 0) {
        err = errno;
        goto out;
    }
    sigchld_installed = true;

    while (!sched->quit) {
        uint64_t now = eco_time_now();
        int next_time;
        int nfds;

        eco_process_timeouts(sched, L, now);

        eco_process_sigchld(L, sched);

        if (sched->quit)
            break;

        next_time = get_next_timeout(sched, now);

        if (next_time < 0 && sched->nfd < 1)
            break;

        nfds = epoll_wait(sched->epoll_fd, events, MAX_EVENTS, next_time);
        if (nfds < 0) {
            if (errno == EINTR) {
                if (got_sigint)
                    break;

                continue;
            }

            err = errno;
            goto out;
        }

        eco_process_io(L, nfds, events);

        if (got_sigint)
            break;
    }

    eco_process_sigchld(L, sched);

    lua_pushboolean(L, true);

out:
    if (sigpipe_installed)
        sigaction(SIGPIPE, &old_sigpipe, NULL);

    if (sigchld_installed)
        sigaction(SIGCHLD, &old_sigchld, NULL);

    if (sigint_installed)
        sigaction(SIGINT, &old_sigint, NULL);

    if (err) {
        lua_pushstring(L, strerror(errno));
        return 1;
    }

    return 0;
}

/**
 * Stop the eco scheduler main loop.
 *
 * @function unloop
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
    pid_t curpid = getpid();
    int epoll_fd;
    int i;

    if (curpid == sched->pid)
        return luaL_error(L, "eco._init() is only allowed in child process after fork()");

    close(sched->epoll_fd);

    epoll_fd = epoll_create1(0);
    if (epoll_fd < 0)
        return luaL_error(L, "failed to create epoll: %s", strerror(errno));

    sched->epoll_fd = epoll_fd;
    sched->pid = curpid;

    INIT_LIST_HEAD(&sched->timer_cache);
    INIT_LIST_HEAD(&sched->timers);
    for (i = 0; i < FD_HASH_BUCKETS; i++)
        INIT_LIST_HEAD(&sched->fds[i]);

    sched->nfd = 0;
    sched->quit = false;
    sched->resumed_at = 0;
    sched->co_run_timeout = CO_RUN_TIMEOUT;

    lua_newtable(L);
    lua_rawsetp(L, LUA_REGISTRYINDEX, &eco_co_key);

    return 0;
}

static int lua_eco_set_sigchld_hook(lua_State *L)
{
    struct eco_scheduler *sched = get_eco_scheduler(L);
    return eco_set_callback_ref(L, 1, &sched->sigchld_hook);
}

static const struct luaL_Reg funcs[] = {
    {"io", lua_eco_io},
    {"reader", lua_eco_reader},
    {"writer", lua_eco_writer},
    {"sleep", lua_eco_sleep},
    {"run", lua_eco_run},
    {"resume", lua_eco_resume},
    {"count", lua_eco_count},
    {"all", lua_eco_all},
    {"set_panic_hook", lua_eco_set_panic_hook},
    {"set_watchdog_timeout", lua_eco_set_watchdog_timeout},
    {"loop", lua_eco_loop},
    {"unloop", lua_eco_unloop},
    {"_init", lua_eco_init},
    {"_set_sigchld_hook", lua_eco_set_sigchld_hook},
    {NULL, NULL}
};

int luaopen_eco(lua_State *L)
{
    eco_scheduler_init(L);

    creat_metatable(L, ECO_IO_MT, io_metatable, io_methods);
    creat_metatable(L, ECO_READER_MT, reader_metatable, reader_methods);
    creat_metatable(L, ECO_WRITER_MT, writer_metatable, writer_methods);

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
