/* SPDX-License-Identifier: MIT */
/*
 * Author: Jianhui Zhao <zhaojh329@gmail.com>
 */

#include <sys/sysinfo.h>
#include <sys/prctl.h>
#include <stdbool.h>
#include <signal.h>
#include <unistd.h>
#include <stdlib.h>
#include <errno.h>

#include "eco.h"

static int lua_uptime(lua_State *L)
{
    struct sysinfo info = {};

    sysinfo(&info);
    lua_pushinteger(L, info.uptime);

    return 1;
}

static int lua_getpid(lua_State *L)
{
    lua_pushinteger(L, getpid());
    return 1;
}

static int lua_getppid(lua_State *L)
{
    lua_pushinteger(L, getppid());
    return 1;
}

static int lua_kill(lua_State *L)
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

static int lua_exec(lua_State *L)
{
    const char *cmd = luaL_checkstring(L, 1);
    int n = lua_gettop(L);
    int opipe[2] = {};
    int epipe[2] = {};
    pid_t pid;

    if (pipe(opipe) < 0 || pipe(epipe) < 0) {
        lua_pushnil(L);
        lua_pushfstring(L, "pipe: %s", strerror(errno));
        goto err;
    }

    pid = fork();
    if (pid < 0) {
        lua_pushnil(L);
        lua_pushfstring(L, "fork: %s", strerror(errno));
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

        execvp(cmd, (char *const *)args);

        fprintf(stderr, "%s: %s", cmd, strerror(errno));
        free(args);
        exit(127);
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

static int lua_spawn(lua_State *L)
{
    pid_t pid;

    luaL_checktype(L, 1, LUA_TFUNCTION);

    pid = fork();
    if (pid < 0) {
        lua_pushnil(L);
        lua_pushstring(L, strerror(errno));
        return 2;
    }

    if (pid == 0) {
        struct eco_context *ctx = eco_get_context(L);
        int error;

        prctl(PR_SET_PDEATHSIG, SIGKILL);

        ev_break(ctx->loop, 0);

        lua_getglobal(L, "eco");
        lua_getfield(L, -1, "run");
        lua_remove(L, -2);
        lua_insert(L, 1);

        error = lua_pcall(L, lua_gettop(L) - 1, 0, 0);
        if (error) {
            fprintf(stderr, "%s\n", lua_tostring(L, -1));
            goto err;
        }

        ev_run(ctx->loop, 0);
err:
        ev_default_destroy();
        exit(0);
    }

    lua_pushinteger(L, pid);
    return 1;
}

static int lua_get_nprocs(lua_State *L)
{
    int nprocs = get_nprocs();

    lua_pushinteger(L, nprocs);

    return 1;
}

static int lua_strerror(lua_State *L)
{
    int no = luaL_checkinteger(L, 1);

    lua_pushstring(L, strerror(no));
    return 1;
}

static const luaL_Reg funcs[] = {
    {"uptime", lua_uptime},
    {"getpid", lua_getpid},
    {"getppid", lua_getppid},
    {"kill", lua_kill},
    {"exec", lua_exec},
    {"spawn", lua_spawn},
    {"get_nprocs", lua_get_nprocs},
    {"strerror", lua_strerror},
    {NULL, NULL}
};

int luaopen_eco_core_sys(lua_State *L)
{
    luaL_newlib(L, funcs);

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
    lua_add_constant(L, "EPERM", EPERM);
    lua_add_constant(L, "ENOENT", ENOENT);
    lua_add_constant(L, "ESRCH", ESRCH);
    lua_add_constant(L, "EINTR", EINTR);
    lua_add_constant(L, "EIO", EIO);
    lua_add_constant(L, "ENXIO", ENXIO);
    lua_add_constant(L, "E2BIG", E2BIG);
    lua_add_constant(L, "ENOEXEC", ENOEXEC);
    lua_add_constant(L, "EBADF", EBADF);
    lua_add_constant(L, "ECHILD", ECHILD);
    lua_add_constant(L, "EAGAIN", EAGAIN);
    lua_add_constant(L, "ENOMEM", ENOMEM);
    lua_add_constant(L, "EACCES", EACCES);
    lua_add_constant(L, "EFAULT", EFAULT);
    lua_add_constant(L, "ENOTBLK", ENOTBLK);
    lua_add_constant(L, "EBUSY", EBUSY);
    lua_add_constant(L, "EEXIST", EEXIST);
    lua_add_constant(L, "EXDEV", EXDEV);
    lua_add_constant(L, "ENODEV", ENODEV);
    lua_add_constant(L, "ENOTDIR", ENOTDIR);
    lua_add_constant(L, "EISDIR", EISDIR);
    lua_add_constant(L, "EINVAL", EINVAL);
    lua_add_constant(L, "ENFILE", ENFILE);
    lua_add_constant(L, "EMFILE", EMFILE);
    lua_add_constant(L, "ENOTTY", ENOTTY);
    lua_add_constant(L, "ETXTBSY", ETXTBSY);
    lua_add_constant(L, "EFBIG", EFBIG);
    lua_add_constant(L, "ENOSPC", ENOSPC);
    lua_add_constant(L, "ESPIPE", ESPIPE);
    lua_add_constant(L, "EROFS", EROFS);
    lua_add_constant(L, "EMLINK", EMLINK);
    lua_add_constant(L, "EPIPE", EPIPE);
    lua_add_constant(L, "EDOM", EDOM);
    lua_add_constant(L, "ERANGE", ERANGE);
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
