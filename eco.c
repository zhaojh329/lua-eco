#include <lauxlib.h>
#include <lualib.h>
#include <lua.h>

#include <sys/epoll.h>
#include <sys/time.h>
#include <stdbool.h>
#include <stdlib.h>
#include <stdint.h>
#include <fcntl.h>
#include <time.h>

#include "helper.h"
#include "list.h"

static const char *eco_scheduler_registry = "eco-scheduler";

#define MAX_EVENTS 128

#define MAX_IO_CACHE   32
#define MAX_TIMER_CACHE 32

struct eco_scheduler {
    struct list_head io_cache;
    struct list_head timer_cache;
    struct list_head timers;
    size_t io_cache_size;
    size_t timer_cache_size;
    int epoll_fd;
};

struct eco_timer {
	struct list_head list;
	struct timeval tv;
    int ref;
    void *data;
};

struct eco_io {
    struct list_head list;
    struct eco_timer *tmr;
    int ref;
    int fd;
};

static struct eco_io *eco_io_alloc(struct eco_scheduler *sched)
{
    struct eco_io *io;

    if (list_empty(&sched->io_cache)) {
        io = malloc(sizeof(struct eco_io));
    } else {
        io = (struct eco_io *)list_first_entry(&sched->io_cache, struct eco_io, list);
        list_del(&io->list);
        sched->io_cache_size--;
    }

    io->tmr = NULL;
    io->ref = LUA_NOREF;

    return io;
}

static void eco_io_free(struct eco_scheduler *sched, struct eco_io *cc)
{
    if (sched->io_cache_size == MAX_IO_CACHE) {
        free(cc);
        return;
    }

    list_add_tail(&cc->list, &sched->io_cache);
    sched->io_cache_size++;
}

static void eco_gettime(struct timeval *tv)
{
	struct timespec ts;

	clock_gettime(CLOCK_MONOTONIC, &ts);
	tv->tv_sec = ts.tv_sec;
	tv->tv_usec = ts.tv_nsec / 1000;
}

static int64_t tv_diff(struct timeval *t1, struct timeval *t2)
{
	return (t1->tv_sec - t2->tv_sec) * 1000 + (t1->tv_usec - t2->tv_usec) / 1000;
}

static struct eco_timer *eco_timer_alloc(struct eco_scheduler *sched, double second)
{
    struct list_head *h = &sched->timers;
    struct eco_timer *tmp, *tmr;
    struct timeval *tv;
    int ms = second * 1000;

    if (list_empty(&sched->timer_cache)) {
        tmr = malloc(sizeof(struct eco_timer));
    } else {
        tmr = (struct eco_timer *)list_first_entry(&sched->timer_cache, struct eco_timer, list);
        list_del(&tmr->list);
        sched->timer_cache_size--;
    }

    tv = &tmr->tv;

    eco_gettime(tv);

	tv->tv_sec += ms / 1000;
	tv->tv_usec += (ms % 1000) * 1000;

	list_for_each_entry(tmp, &sched->timers, list) {
		if (tv_diff(&tmp->tv, &tmr->tv) > 0) {
			h = &tmp->list;
			break;
		}
	}

	list_add_tail(&tmr->list, h);

    tmr->ref = LUA_NOREF;
    tmr->data = NULL;

    return tmr;
}

static void eco_timer_free(struct eco_scheduler *sched, struct eco_timer *tmr)
{
    list_del(&tmr->list);

    if (sched->timer_cache_size == MAX_TIMER_CACHE) {
        free(tmr);
        return;
    }

    list_add_tail(&tmr->list, &sched->timer_cache);
    sched->timer_cache_size++;
}

static int eco_scheduler_init(lua_State *L)
{
    struct eco_scheduler *sched = calloc(1, sizeof(struct eco_scheduler));

    sched->epoll_fd = epoll_create1(0);

    INIT_LIST_HEAD(&sched->io_cache);
    INIT_LIST_HEAD(&sched->timer_cache);
    INIT_LIST_HEAD(&sched->timers);

    lua_pushlightuserdata(L, sched);
    lua_rawsetp(L, LUA_REGISTRYINDEX, &eco_scheduler_registry);

    return 0;
}

static struct eco_scheduler *get_eco_scheduler(lua_State *L)
{
    struct eco_scheduler *sched;

    lua_rawgetp(L, LUA_REGISTRYINDEX, &eco_scheduler_registry);

    if (lua_isnil(L, -1)) {
        lua_pop(L, 1);
        eco_scheduler_init(L);
        lua_rawgetp(L, LUA_REGISTRYINDEX, &eco_scheduler_registry);
    }

    sched = (struct eco_scheduler *)lua_topointer(L, -1);

    lua_pop(L, 1);

    return sched;
}

static int lua_eco_sleep(lua_State *L)
{
    double delay = luaL_checknumber(L, 1);
    struct eco_scheduler *sched = get_eco_scheduler(L);
    struct eco_timer *tmr = eco_timer_alloc(sched, delay);

    lua_pushthread(L);
    tmr->ref = luaL_ref(L, LUA_REGISTRYINDEX);

    return lua_yield(L, 0);
}

static int lua_eco_io(lua_State *L, uint32_t event)
{
    int fd = luaL_checkinteger(L, 1);
    double timeout = lua_tonumber(L, 2);
    struct eco_scheduler *sched = get_eco_scheduler(L);
    struct eco_io *io = eco_io_alloc(sched);
    struct epoll_event ev;
    int flags;

    flags = fcntl(fd, F_GETFL, 0);
    fcntl(fd, F_SETFL, flags | O_NONBLOCK);

    io->fd = fd;
    io->tmr = NULL;

    lua_pushthread(L);
    io->ref = luaL_ref(L, LUA_REGISTRYINDEX);

    if (timeout > 0) {
        struct eco_timer *tmr = eco_timer_alloc(sched, timeout);
        tmr->ref = LUA_NOREF;
        tmr->data = io;
        io->tmr = tmr;
    }

    ev.events = event | EPOLLET;
    ev.data.ptr = io;

    epoll_ctl(sched->epoll_fd, EPOLL_CTL_ADD, fd, &ev);

    return lua_yield(L, 0);
}

static int lua_eco_read(lua_State *L)
{
    return lua_eco_io(L, EPOLLIN);
}

static int lua_eco_write(lua_State *L)
{
    return lua_eco_io(L, EPOLLOUT);
}

static int lua_eco_run(lua_State *L)
{
    int top = lua_gettop(L);
    lua_State *co;
    int nres;

    luaL_checktype(L, 1, LUA_TFUNCTION); /* func, a1, a2,... */

    co = lua_newthread(L);  /* func, a1, a2,..., co */

    lua_rotate(L, 1, 1);    /* co, func, a1, a2,... */
    lua_xmove(L, co, top);  /* co */

    lua_resume(co, L, top - 1, &nres);

    return 1;
}

static int get_next_timeout(struct eco_scheduler *sched)
{
    struct eco_timer *tmr;
    struct timeval tv;
    int64_t diff;

    if (list_empty(&sched->timers))
        return -1;

    eco_gettime(&tv);

    tmr = list_first_entry(&sched->timers, struct eco_timer, list);

    diff = tv_diff(&tmr->tv, &tv);

    if (diff < 0)
        return 0;

    if (diff > INT_MAX)
        return INT_MAX;

    return diff;
}

static void eco_resume(lua_State *L, int ref, bool ok)
{
    lua_State *co;
    int nres;

    lua_rawgeti(L, LUA_REGISTRYINDEX, ref);

    co = lua_tothread(L, -1);
    lua_pop(L, 1);

    luaL_unref(L, LUA_REGISTRYINDEX, ref);
    lua_pushboolean(co, ok);
    lua_resume(co, L, 1, &nres);
}

static void eco_process_timeouts(struct eco_scheduler *sched, lua_State *L)
{
	struct eco_timer *tmr;
	struct timeval tv;
    int ref;

	if (list_empty(&sched->timers))
		return;

    eco_gettime(&tv);

	while (!list_empty(&sched->timers)) {
		tmr = list_first_entry(&sched->timers, struct eco_timer, list);
        ref = tmr->ref;

		if (tv_diff(&tmr->tv, &tv) > 0)
			break;

		if (ref != LUA_NOREF) {
            eco_timer_free(sched, tmr);
			eco_resume(L, ref, true);
		} else {
			struct eco_io *io = (struct eco_io *)tmr->data;

            epoll_ctl(sched->epoll_fd, EPOLL_CTL_DEL, io->fd, NULL);
            eco_timer_free(sched, tmr);
			eco_io_free(sched, io);
			eco_resume(L, io->ref, false);
		}
	}
}

static void eco_process_fds(struct eco_scheduler *sched, lua_State *L,
            int nfds, struct epoll_event *events)
{
    for (int i = 0; i < nfds; i++) {
        struct eco_io *io = events[i].data.ptr;
        int ref = io->ref;

        if (io->tmr)
            eco_timer_free(sched, io->tmr);

        epoll_ctl(sched->epoll_fd, EPOLL_CTL_DEL, io->fd, NULL);
        eco_io_free(sched, io);
        eco_resume(L, ref, true);
    }
}

static int lua_eco_loop(lua_State *L)
{
    struct eco_scheduler *sched = get_eco_scheduler(L);
    struct epoll_event events[MAX_EVENTS];
    int next_time;
    int nfds;

    while (true) {
        eco_process_timeouts(sched, L);

        next_time = get_next_timeout(sched);

        nfds = epoll_wait(sched->epoll_fd, events, MAX_EVENTS, next_time);

        eco_process_fds(sched, L, nfds, events);
    }

    return 0;
}

static const struct luaL_Reg funcs[] = {
    {"sleep", lua_eco_sleep},
    {"read", lua_eco_read},
    {"write", lua_eco_write},
    {"run", lua_eco_run},
    {"loop", lua_eco_loop},
    {NULL, NULL}
};

int luaopen_eco(lua_State *L)
{
    luaL_newlib(L, funcs);

    return 1;
}
