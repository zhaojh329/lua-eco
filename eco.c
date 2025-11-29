#include <lauxlib.h>
#include <lualib.h>
#include <lua.h>

#include <sys/epoll.h>
#include <sys/time.h>
#include <stdbool.h>
#include <stdlib.h>
#include <fcntl.h>
#include <time.h>

#include "helper.h"
#include "list.h"

static const char *eco_scheduler_registry = "eco-scheduler";

#define MAX_EVENTS 128

#define MAX_ECO_CACHE   32
#define MAX_TIMER_CACHE 32

struct eco_scheduler {
    struct list_head eco_cache;
    struct list_head timer_cache;
    struct list_head timers;
    size_t eco_cache_size;
    size_t timer_cache_size;
    int epoll_fd;
};

struct eco_context {
    struct list_head list;
    int ref;
    int fd;
};

struct eco_timer {
	struct list_head list;
	struct timeval tv;
    int ref;
};

static struct eco_context *eco_context_alloc(struct eco_scheduler *sched)
{
    struct eco_context *cc;

    if (list_empty(&sched->eco_cache)) {
        cc = malloc(sizeof(struct eco_context));
    } else {
        cc = (struct eco_context *)list_first_entry(&sched->eco_cache, struct eco_context, list);
        list_del(&cc->list);
        sched->eco_cache_size--;
    }

    return cc;
}

static void eco_context_free(struct eco_scheduler *sched, struct eco_context *cc)
{
    if (sched->eco_cache_size == MAX_ECO_CACHE) {
        free(cc);
        return;
    }

    list_add_tail(&cc->list, &sched->eco_cache);
    sched->eco_cache_size++;
}

static struct eco_timer *eco_timer_alloc(struct eco_scheduler *sched)
{
    struct eco_timer *tmr;

    if (list_empty(&sched->timer_cache)) {
        tmr = malloc(sizeof(struct eco_timer));
    } else {
        tmr = (struct eco_timer *)list_first_entry(&sched->timer_cache, struct eco_timer, list);
        list_del(&tmr->list);
        sched->timer_cache_size--;
    }

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

    INIT_LIST_HEAD(&sched->eco_cache);
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

static int64_t tv_diff(struct timeval *t1, struct timeval *t2)
{
	return (t1->tv_sec - t2->tv_sec) * 1000 + (t1->tv_usec - t2->tv_usec) / 1000;
}

static void eco_gettime(struct timeval *tv)
{
	struct timespec ts;

	clock_gettime(CLOCK_MONOTONIC, &ts);
	tv->tv_sec = ts.tv_sec;
	tv->tv_usec = ts.tv_nsec / 1000;
}

static int lua_eco_sleep(lua_State *L)
{
    int delay = luaL_checknumber(L, 1) * 1000;
    struct eco_scheduler *sched = get_eco_scheduler(L);
    struct eco_timer *tmr = eco_timer_alloc(sched);
    struct list_head *h = &sched->timers;
    struct timeval *tv = &tmr->tv;
    struct eco_timer *tmp;

    eco_gettime(tv);

	tv->tv_sec += delay / 1000;
	tv->tv_usec += (delay % 1000) * 1000;

	list_for_each_entry(tmp, &sched->timers, list) {
		if (tv_diff(&tmp->tv, &tmr->tv) > 0) {
			h = &tmp->list;
			break;
		}
	}

	list_add_tail(&tmr->list, h);

    lua_pushthread(L);
    tmr->ref = luaL_ref(L, LUA_REGISTRYINDEX);

    return lua_yield(L, 0);
}

static int lua_eco_io(lua_State *L, uint32_t event)
{
    int fd = luaL_checkinteger(L, 1);
    struct eco_scheduler *sched = get_eco_scheduler(L);
    struct eco_context *cc = eco_context_alloc(sched);
    struct epoll_event ev;
    int flags;

    flags = fcntl(fd, F_GETFL, 0);
    fcntl(fd, F_SETFL, flags | O_NONBLOCK);

    cc->fd = fd;

    lua_pushthread(L);
    cc->ref = luaL_ref(L, LUA_REGISTRYINDEX);

    ev.events = event | EPOLLET;
    ev.data.ptr = cc;

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

    luaL_checktype(L, 1, LUA_TFUNCTION); /* f, a1, a2,... */

    co = lua_newthread(L);  /* f, a1, a2,..., co */

    lua_rotate(L, 1, 1);    /* co, f, a1, a2,... */
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

static void eco_resume(lua_State *L, int ref)
{
    lua_State *co;
    int nres;

    lua_rawgeti(L, LUA_REGISTRYINDEX, ref);

    co = lua_tothread(L, -1);
    lua_pop(L, 1);

    luaL_unref(L, LUA_REGISTRYINDEX, ref);

    lua_resume(co, L, 0, &nres);
}

static void eco_process_timeouts(struct eco_scheduler *sched, lua_State *L)
{
	struct eco_timer *t;
	struct timeval tv;
    int ref;

	if (list_empty(&sched->timers))
		return;

	gettimeofday(&tv, NULL);

	while (!list_empty(&sched->timers)) {
		t = list_first_entry(&sched->timers, struct eco_timer, list);
        ref = t->ref;

		if (tv_diff(&t->tv, &tv) > 0)
			break;

		eco_timer_free(sched, t);
        eco_resume(L, ref);
	}
}

static void eco_process_fds(struct eco_scheduler *sched, lua_State *L,
            int nfds, struct epoll_event *events)
{
    for (int i = 0; i < nfds; i++) {
        struct eco_context *cc = events[i].data.ptr;
        int ref = cc->ref;

        epoll_ctl(sched->epoll_fd, EPOLL_CTL_DEL, cc->fd, NULL);
        eco_context_free(sched, cc);
        eco_resume(L, ref);
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
