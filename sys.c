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
#include <sys/stat.h>
#include <stdbool.h>
#include <string.h>
#include <signal.h>
#include <unistd.h>
#include <stdlib.h>
#include <errno.h>

#include "eco.h"

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

static int eco_sys_kill(lua_State *L)
{
    int pid = luaL_checkinteger(L, 1);
    int sig = luaL_checkinteger(L, 2);
    int ret;

    ret = kill(pid, sig);
    if (ret < 0) {
        lua_pushboolean(L, false);
        lua_pushstring(L, strerror(errno));
        return 2;
    }

    lua_pushboolean(L, true);
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

static int eco_sys_exec(lua_State *L)
{
    const char *cmd = luaL_checkstring(L, 1);
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

        lua_pushinteger(L, pid);
        lua_pushinteger(L, opipe[0]);
        lua_pushinteger(L, epipe[0]);

        return 3;
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

static int eco_sys_strerror(lua_State *L)
{
    int no = luaL_checkinteger(L, 1);

    lua_pushstring(L, strerror(no));
    return 1;
}

int luaopen_eco_core_sys(lua_State *L)
{
    lua_newtable(L);

    lua_pushcfunction(L, eco_sys_uptime);
    lua_setfield(L, -2, "uptime");

    lua_pushcfunction(L, eco_sys_getpid);
    lua_setfield(L, -2, "getpid");

    lua_pushcfunction(L, eco_sys_getppid);
    lua_setfield(L, -2, "getppid");

    lua_pushcfunction(L, eco_sys_kill);
    lua_setfield(L, -2, "kill");

    lua_pushcfunction(L, eco_sys_exec);
    lua_setfield(L, -2, "exec");

    lua_pushcfunction(L, eco_sys_strerror);
    lua_setfield(L, -2, "strerror");

    /* signal */
    lua_add_constant(L, "SIGABRT", SIGABRT);
    lua_add_constant(L, "SIGALRM", SIGALRM);
    lua_add_constant(L, "SIGBUS", SIGBUS);
    lua_add_constant(L, "SIGCHLD", SIGCHLD);
    lua_add_constant(L, "SIGCONT", SIGCONT);
    lua_add_constant(L, "SIGFPE", SIGFPE);
    lua_add_constant(L, "SIGHUP", SIGHUP);
    lua_add_constant(L, "SIGINT", SIGINT);
    lua_add_constant(L, "SIGIO", SIGIO);
    lua_add_constant(L, "SIGIOT", SIGIOT);
    lua_add_constant(L, "SIGKILL", SIGKILL);
    lua_add_constant(L, "SIGPIPE", SIGPIPE);
#ifdef SIGPOLL
    lua_add_constant(L, "SIGPOLL", SIGPOLL);
#endif
    lua_add_constant(L, "SIGPROF", SIGPROF);
#ifdef SIGPWR
    lua_add_constant(L, "SIGPWR", SIGPWR);
#endif
    lua_add_constant(L, "SIGQUIT", SIGQUIT);
    lua_add_constant(L, "SIGSEGV", SIGSEGV);
#ifdef SIGSTKFLT
    lua_add_constant(L, "SIGSTKFLT", SIGSTKFLT);
#endif
    lua_add_constant(L, "SIGSYS", SIGSYS);
    lua_add_constant(L, "SIGTERM", SIGTERM);
    lua_add_constant(L, "SIGTRAP", SIGTRAP);
    lua_add_constant(L, "SIGTSTP", SIGTSTP);
    lua_add_constant(L, "SIGTTIN", SIGTTIN);
    lua_add_constant(L, "SIGTTOU", SIGTTOU);
    lua_add_constant(L, "SIGURG", SIGURG);
    lua_add_constant(L, "SIGUSR1", SIGUSR1);
    lua_add_constant(L, "SIGUSR2", SIGUSR2);
    lua_add_constant(L, "SIGVTALRM", SIGVTALRM);
    lua_add_constant(L, "SIGWINCH", SIGWINCH);
    lua_add_constant(L, "SIGXCPU", SIGXCPU);
    lua_add_constant(L, "SIGXFSZ", SIGXFSZ);

    /* errno */
    lua_add_constant(L, "EDEADLK", EDEADLK);
    lua_add_constant(L, "ENAMETOOLONG", ENAMETOOLONG);
    lua_add_constant(L, "ENOLCK", ENOLCK);
    lua_add_constant(L, "ENOSYS", ENOSYS);
    lua_add_constant(L, "ENOTEMPTY", ENOTEMPTY);
    lua_add_constant(L, "ELOOP", ELOOP);
    lua_add_constant(L, "EWOULDBLOCK", EWOULDBLOCK);
    lua_add_constant(L, "ENOMSG", ENOMSG);
    lua_add_constant(L, "EIDRM", EIDRM);
    lua_add_constant(L, "ECHRNG", ECHRNG);
    lua_add_constant(L, "ELNSYNC", EL2NSYNC);
    lua_add_constant(L, "ELHLT", EL3HLT);
    lua_add_constant(L, "ELRST", EL3RST);
    lua_add_constant(L, "ELNRNG", ELNRNG);
    lua_add_constant(L, "EUNATCH", EUNATCH);
    lua_add_constant(L, "ENOCSI", ENOCSI);
    lua_add_constant(L, "ELHLT", EL2HLT);
    lua_add_constant(L, "EBADE", EBADE);
    lua_add_constant(L, "EBADR", EBADR);
    lua_add_constant(L, "EXFULL", EXFULL);
    lua_add_constant(L, "ENOANO", ENOANO);
    lua_add_constant(L, "EBADRQC", EBADRQC);
    lua_add_constant(L, "EBADSLT", EBADSLT);
    lua_add_constant(L, "EDEADLOCK", EDEADLOCK);
    lua_add_constant(L, "EBFONT", EBFONT);
    lua_add_constant(L, "ENOSTR", ENOSTR);
    lua_add_constant(L, "ENODATA", ENODATA);
    lua_add_constant(L, "ETIME", ETIME);
    lua_add_constant(L, "ENOSR", ENOSR);
    lua_add_constant(L, "ENONET", ENONET);
    lua_add_constant(L, "ENOPKG", ENOPKG);
    lua_add_constant(L, "EREMOTE", EREMOTE);
    lua_add_constant(L, "ENOLINK", ENOLINK);
    lua_add_constant(L, "EADV", EADV);
    lua_add_constant(L, "ESRMNT", ESRMNT);
    lua_add_constant(L, "ECOMM", ECOMM);
    lua_add_constant(L, "EPROTO", EPROTO);
    lua_add_constant(L, "EMULTIHOP", EMULTIHOP);
    lua_add_constant(L, "EDOTDOT", EDOTDOT);
    lua_add_constant(L, "EBADMSG", EBADMSG);
    lua_add_constant(L, "EOVERFLOW", EOVERFLOW);
    lua_add_constant(L, "ENOTUNIQ", ENOTUNIQ);
    lua_add_constant(L, "EBADFD", EBADFD);
    lua_add_constant(L, "EREMCHG", EREMCHG);
    lua_add_constant(L, "ELIBACC", ELIBACC);
    lua_add_constant(L, "ELIBBAD", ELIBBAD);
    lua_add_constant(L, "ELIBSCN", ELIBSCN);
    lua_add_constant(L, "ELIBMAX", ELIBMAX);
    lua_add_constant(L, "ELIBEXEC", ELIBEXEC);
    lua_add_constant(L, "EILSEQ", EILSEQ);
    lua_add_constant(L, "ERESTART", ERESTART);
    lua_add_constant(L, "ESTRPIPE", ESTRPIPE);
    lua_add_constant(L, "EUSERS", EUSERS);
    lua_add_constant(L, "ENOTSOCK", ENOTSOCK);
    lua_add_constant(L, "EDESTADDRREQ", EDESTADDRREQ);
    lua_add_constant(L, "EMSGSIZE", EMSGSIZE);
    lua_add_constant(L, "EPROTOTYPE", EPROTOTYPE);
    lua_add_constant(L, "ENOPROTOOPT", ENOPROTOOPT);
    lua_add_constant(L, "EPROTONOSUPPORT", EPROTONOSUPPORT);
    lua_add_constant(L, "ESOCKTNOSUPPORT", ESOCKTNOSUPPORT);
    lua_add_constant(L, "EOPNOTSUPP", EOPNOTSUPP);
    lua_add_constant(L, "EPFNOSUPPORT", EPFNOSUPPORT);
    lua_add_constant(L, "EAFNOSUPPORT", EAFNOSUPPORT);
    lua_add_constant(L, "EADDRINUSE", EADDRINUSE);
    lua_add_constant(L, "EADDRNOTAVAIL", EADDRNOTAVAIL);
    lua_add_constant(L, "ENETDOWN", ENETDOWN);
    lua_add_constant(L, "ENETUNREACH", ENETUNREACH);
    lua_add_constant(L, "ENETRESET", ENETRESET);
    lua_add_constant(L, "ECONNABORTED", ECONNABORTED);
    lua_add_constant(L, "ECONNRESET", ECONNRESET);
    lua_add_constant(L, "ENOBUFS", ENOBUFS);
    lua_add_constant(L, "EISCONN", EISCONN);
    lua_add_constant(L, "ENOTCONN", ENOTCONN);
    lua_add_constant(L, "ESHUTDOWN", ESHUTDOWN);
    lua_add_constant(L, "ETOOMANYREFS", ETOOMANYREFS);
    lua_add_constant(L, "ETIMEDOUT", ETIMEDOUT);
    lua_add_constant(L, "ECONNREFUSED", ECONNREFUSED);
    lua_add_constant(L, "EHOSTDOWN", EHOSTDOWN);
    lua_add_constant(L, "EHOSTUNREACH", EHOSTUNREACH);
    lua_add_constant(L, "EALREADY", EALREADY);
    lua_add_constant(L, "EINPROGRESS", EINPROGRESS);
    lua_add_constant(L, "ESTALE", ESTALE);
    lua_add_constant(L, "EUCLEAN", EUCLEAN);
    lua_add_constant(L, "ENOTNAM", ENOTNAM);
    lua_add_constant(L, "ENAVAIL", ENAVAIL);
    lua_add_constant(L, "EISNAM", EISNAM);
    lua_add_constant(L, "EREMOTEIO", EREMOTEIO);
    lua_add_constant(L, "EDQUOT", EDQUOT);
    lua_add_constant(L, "ENOMEDIUM", ENOMEDIUM);
    lua_add_constant(L, "EMEDIUMTYPE", EMEDIUMTYPE);
    lua_add_constant(L, "ECANCELED", ECANCELED);
    lua_add_constant(L, "ENOKEY", ENOKEY);
    lua_add_constant(L, "EKEYEXPIRED", EKEYEXPIRED);
    lua_add_constant(L, "EKEYREVOKED", EKEYREVOKED);
    lua_add_constant(L, "EKEYREJECTED", EKEYREJECTED);
    lua_add_constant(L, "EOWNERDEAD", EOWNERDEAD);
    lua_add_constant(L, "ENOTRECOVERABLE", ENOTRECOVERABLE);
    lua_add_constant(L, "ERFKILL", ERFKILL);
    lua_add_constant(L, "EHWPOISON", EHWPOISON);

    return 1;
}
