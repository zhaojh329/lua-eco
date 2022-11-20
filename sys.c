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

#include <sys/sysinfo.h>
#include <sys/types.h>
#include <unistd.h>
#include <stdlib.h>
#include <errno.h>

#include "eco.h"

struct eco_sys_exec {
    struct eco_context *ctx;
    struct ev_child proc;
    struct ev_io out;
    struct ev_io err;
    struct ev_timer tmr;
    double wait_timeout;
    double read_timeout;
    int out_fd;
    int err_fd;
    bool exited;
    pid_t pid;
    int code;
    lua_State *co;
};

static int eco_sys_uptime(lua_State *L)
{
    struct sysinfo info = {};

    sysinfo(&info);
    lua_pushnumber(L, info.uptime);

    return 1;
}

static int eco_sys_getpid(lua_State *L)
{
    lua_pushinteger(L, getpid());
    return 1;
}

static int eco_sys_getppid(lua_State *L)
{
    lua_pushinteger(L, getppid());
    return 1;
}

static int file_is_executable(const char *name)
{
    struct stat s;
    return (!access(name, X_OK) && !stat(name, &s) && S_ISREG(s.st_mode));
}

static char *concat_path_file(const char *path, const char *filename)
{
    bool end_with_slash = path[strlen(path) - 1] == '/';
    char *strp;

    while (*filename == '/')
        filename++;
    if (asprintf(&strp, "%s%s%s", path, (end_with_slash ? "" : "/"), filename) < 0)
        return NULL;
    return strp;
}

static char *find_executable(const char *filename, char **path)
{
    char *p, *n;

    p = *path;
    while (p) {
        int ex;

        n = strchr(p, ':');
        if (n) *n = '\0';
        p = concat_path_file(p[0] ? p : ".", filename);
        if (!p)
            break;
        ex = file_is_executable(p);
        if (n) *n++ = ':';
        if (ex) {
            *path = n;
            return p;
        }
        free(p);
        p = n;
    } /* on loop exit p == NULL */
    return p;
}

static int which(const char *prog)
{
    char buf[] = "/sbin:/usr/sbin:/bin:/usr/bin";
    char *env_path;
    int missing = 1;

    env_path = getenv("PATH");
    if (!env_path)
        env_path = buf;

    /* If file contains a slash don't use PATH */
    if (strchr(prog, '/')) {
        if (file_is_executable(prog))
            missing = 0;
    } else {
        char *path;
        char *p;

        path = env_path;

        while ((p = find_executable(prog, &path))) {
            missing = 0;
            free(p);
            break;
        }
    }
    return missing;
}

static void eco_sys_exec_clean(struct eco_sys_exec *proc)
{
    struct ev_loop *loop = proc->ctx->loop;

    if (proc->exited)
        return;

    ev_child_stop(loop, &proc->proc);
    ev_timer_stop(loop, &proc->tmr);
    ev_io_stop(loop, &proc->out);
    ev_io_stop(loop, &proc->err);

    close(proc->out_fd);
    close(proc->err_fd);
}

static int eco_sys_exec_gc(lua_State *L)
{
    struct eco_sys_exec *proc = lua_touserdata(L, 1);

    eco_sys_exec_clean(proc);

    return 0;
}

static void eco_exec_timer_cb(struct ev_loop *loop, struct ev_timer *w, int revents)
{
    struct eco_sys_exec *proc = container_of(w, struct eco_sys_exec, tmr);
    lua_State *co = proc->co;

    lua_pushnil(co);
    lua_pushliteral(co, "timeout");

    eco_resume(proc->ctx->L, co, 2);
}

static void eco_exec_child_cb(struct ev_loop *loop, struct ev_child *w, int revents)
{
    struct eco_sys_exec *proc = container_of(w, struct eco_sys_exec, proc);
    lua_State *co = proc->co;

    if (w->pid != w->rpid)
        return;

    eco_sys_exec_clean(proc);

    proc->exited = true;
    proc->code = WEXITSTATUS(w->rstatus);

    if (co) {
        proc->co = NULL;
        lua_pushinteger(co, proc->code);
        eco_resume(proc->ctx->L, co, 1);
    }
}

static void eco_exec_read_cb(struct ev_loop *loop, struct ev_io *w, struct eco_sys_exec *proc)
{
    lua_State *co = proc->co;
    char buf[4096];
    int narg = 1;
    int r;

    ev_io_stop(loop, w);

    r = read(w->fd, buf, sizeof(buf));
    if (r <= 0) {
        narg++;
        lua_pushnil(co);

        if (r == 0)
            lua_pushliteral(co, "exited");
        else
            lua_pushstring(co, strerror(errno));
    }

    proc->co = NULL;

    lua_pushlstring(co, buf, r);
    eco_resume(proc->ctx->L, co, narg);
}

static void eco_exec_stdout_cb(struct ev_loop *loop, struct ev_io *w, int revents)
{
    struct eco_sys_exec *proc = container_of(w, struct eco_sys_exec, out);
    eco_exec_read_cb(loop, w, proc);
}

static void eco_exec_stderr_cb(struct ev_loop *loop, struct ev_io *w, int revents)
{
    struct eco_sys_exec *proc = container_of(w, struct eco_sys_exec, err);
    eco_exec_read_cb(loop, w, proc);
}

static int eco_sys_exec_read(lua_State *L, bool is_stderr)
{
    struct eco_sys_exec *proc = lua_touserdata(L, 1);
    struct ev_loop *loop = proc->ctx->loop;
    struct ev_io *w = &proc->out;

    if (proc->exited) {
        lua_pushnil(L);
        lua_pushliteral(L, "exited");
        return 2;
    }

    if (is_stderr)
        w = &proc->err;

    if (proc->read_timeout > 0) {
        ev_timer_set(&proc->tmr, proc->read_timeout, 0);
        ev_timer_start(loop, &proc->tmr);
    }

    proc->co = L;
    ev_io_start(loop, w);
    return lua_yield(L, 0);
}

static int eco_sys_exec_stdout_read(lua_State *L)
{
    return eco_sys_exec_read(L, false);
}

static int eco_sys_exec_stderr_read(lua_State *L)
{
    return eco_sys_exec_read(L, true);
}

static int eco_sys_exec_wait(lua_State *L)
{
    struct eco_sys_exec *proc = lua_touserdata(L, 1);
    struct ev_loop *loop = proc->ctx->loop;

    if (proc->exited) {
        lua_pushinteger(L, proc->code);
        return 1;
    }

    if (proc->wait_timeout > 0) {
        ev_timer_set(&proc->tmr, proc->wait_timeout, 0);
        ev_timer_start(loop, &proc->tmr);
    }

    proc->co = L;
    return lua_yield(L, 0);
}

static int eco_sys_exec_kill(lua_State *L)
{
    struct eco_sys_exec *proc = lua_touserdata(L, 1);
    int sig = luaL_checkinteger(L, 2);

    if (proc->exited)
        return 0;

    kill(proc->pid, sig);
    return 0;
}

static int eco_sys_exec_settimeout(lua_State *L)
{
    struct eco_sys_exec *proc = lua_touserdata(L, 1);
    const char *type = luaL_checkstring(L, 2);
    double timeout = luaL_checknumber(L, 3);

    if (type[0] == 'w')
        proc->wait_timeout = timeout;
    else if (type[0] == 'r')
        proc->read_timeout = timeout;

    return 0;
}

static int eco_sys_exec(lua_State *L)
{
    struct eco_context *ctx = eco_check_context(L);
    const char *cmd = luaL_checkstring(L, 1);
    struct ev_loop *loop = ctx->loop;
    struct eco_sys_exec *proc;
    int n = lua_gettop(L);
    int opipe[2] = {};
    int epipe[2] = {};
    pid_t pid;

    if (!cmd || which(cmd)) {
        lua_pushnil(L);
        lua_pushstring(L, "command not found");
        return 2;
    }

    if (pipe(opipe) < 0 || pipe(epipe) < 0)
        goto err;

    pid = fork();
    if (pid < 0) {
        goto err;
    } else if (pid == 0) {
        const char **args;
        int i, j;

        /* close unused read end */
        close(opipe[0]);
        close(epipe[0]);

        /* redirect */
        dup2(opipe[1], STDOUT_FILENO);
        dup2(epipe[1], STDERR_FILENO);
        close(opipe[1]);
        close(epipe[1]);

        args = malloc(sizeof(char *) * 2);
        if (!args)
            exit(1);

        args[0] = cmd;
        args[1] = NULL;

        j = 1;

        for (i = 2; i <= n; i++) {
            const char **tmp = realloc(args, sizeof(char *) * (2 + j));
            if (!tmp)
                exit(1);
            args = tmp;
            args[j++] = lua_tostring(L, i);
            args[j] = NULL;
        }

        execvp(cmd, (char *const *) args);

        free(args);
    } else {
        /* close unused write end */
        close(opipe[1]);
        close(epipe[1]);

        proc = lua_newuserdata(L, sizeof(struct eco_sys_exec));
        memset(proc, 0, sizeof(struct eco_sys_exec));
        lua_pushvalue(L, lua_upvalueindex(1));
        lua_setmetatable(L, -2);

        proc->pid = pid;
        proc->ctx = ctx;
        proc->out_fd = opipe[0];
        proc->err_fd = epipe[0];

        ev_init(&proc->tmr, eco_exec_timer_cb);

        ev_child_init(&proc->proc, eco_exec_child_cb, pid, 0);
        ev_child_start(loop, &proc->proc);

        ev_io_init(&proc->out, eco_exec_stdout_cb, proc->out_fd, EV_READ);
        ev_io_init(&proc->err, eco_exec_stderr_cb, proc->err_fd, EV_READ);

        return 1;
    }

err:
    lua_pushnil(L);
    lua_pushstring(L, strerror(errno));

    if (opipe[0] > 0) {
        close(opipe[0]);
        close(opipe[1]);
    }

    if (epipe[0] > 0) {
        close(epipe[0]);
        close(epipe[1]);
    }

    return 2;
}

static const struct luaL_Reg exec_metatable[] =  {
    {"stdout_read", eco_sys_exec_stdout_read},
    {"stderr_read", eco_sys_exec_stderr_read},
    {"settimeout", eco_sys_exec_settimeout},
    {"wait", eco_sys_exec_wait},
    {"kill", eco_sys_exec_kill},
    {"__gc", eco_sys_exec_gc},
    {NULL, NULL}
};

int luaopen_eco_sys(lua_State *L)
{
    lua_newtable(L);

    lua_pushcfunction(L, eco_sys_uptime);
    lua_setfield(L, -2, "uptime");

    lua_pushcfunction(L, eco_sys_getpid);
    lua_setfield(L, -2, "getpid");

    lua_pushcfunction(L, eco_sys_getppid);
    lua_setfield(L, -2, "getppid");

    eco_new_metatable(L, exec_metatable);
    lua_pushcclosure(L, eco_sys_exec, 1);
    lua_setfield(L, -2, "exec");

    return 1;
}
