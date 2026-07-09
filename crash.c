/* SPDX-License-Identifier: MIT */
/*
 * Author: Jianhui Zhao <zhaojh329@gmail.com>
 */

#include "crash.h"

#ifdef ECO_CRASH_BACKTRACE
#include <signal.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <fcntl.h>
#include <sys/types.h>
#include <unistd.h>

#ifdef ECO_HAVE_LIBUNWIND
#define UNW_LOCAL_ONLY
#include <libunwind.h>
#elif defined(ECO_HAVE_EXECINFO)
#include <execinfo.h>
#endif
#endif

#ifdef ECO_CRASH_BACKTRACE

#define CRASH_MAX_FRAMES 64
#define CRASH_PATH_MAX 4096
#define CRASH_ALTSTACK_SIZE (64 * 1024)

#if defined(__GNUC__)
#define CRASH_ALIGNED(n) __attribute__((aligned(n)))
#else
#define CRASH_ALIGNED(n)
#endif

static unsigned char crash_altstack[CRASH_ALTSTACK_SIZE] CRASH_ALIGNED(16);
static volatile sig_atomic_t crash_handling;
static int crash_fd = STDERR_FILENO;
static char crash_path[CRASH_PATH_MAX];

static void crash_set_path(const char *path)
{
    size_t i;

    if (!path)
        return;

    for (i = 0; path[i]; i++) {
        if (i == sizeof(crash_path) - 1) {
            crash_path[0] = 0;
            return;
        }

        crash_path[i] = path[i];
    }

    crash_path[i] = 0;
}

static void crash_open_file(void)
{
    int fd;

    if (!crash_path[0] || crash_fd != STDERR_FILENO)
        return;

    fd = open(crash_path, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0644);
    if (fd >= 0)
        crash_fd = fd;
}

static void crash_write_buf(const char *s, size_t len)
{
    while (len > 0) {
        ssize_t ret = write(crash_fd, s, len);
        if (ret <= 0)
            return;

        s += ret;
        len -= ret;
    }
}

static void crash_write(const char *s)
{
    size_t len = 0;

    while (s[len])
        len++;

    crash_write_buf(s, len);
}

static void crash_write_dec(long v)
{
    char buf[32];
    char *p = &buf[sizeof(buf)];
    unsigned long n;

    if (v == 0) {
        crash_write("0");
        return;
    }

    if (v < 0) {
        crash_write("-");
        n = (unsigned long)(-v);
    } else {
        n = (unsigned long)v;
    }

    while (n > 0) {
        *--p = (char)('0' + (n % 10));
        n /= 10;
    }

    crash_write_buf(p, (size_t)(&buf[sizeof(buf)] - p));
}

static void crash_write_hex(uintptr_t v)
{
    char buf[2 + sizeof(uintptr_t) * 2];
    static const char hex[] = "0123456789abcdef";
    size_t i;

    buf[0] = '0';
    buf[1] = 'x';

    for (i = 0; i < sizeof(uintptr_t) * 2; i++) {
        size_t shift = (sizeof(uintptr_t) * 2 - 1 - i) * 4;
        buf[2 + i] = hex[(v >> shift) & 0xf];
    }

    crash_write_buf(buf, sizeof(buf));
}

static const char *crash_signal_name(int sig)
{
    switch (sig) {
    case SIGSEGV:
        return "SIGSEGV";
    case SIGABRT:
        return "SIGABRT";
    case SIGBUS:
        return "SIGBUS";
    case SIGILL:
        return "SIGILL";
    case SIGFPE:
        return "SIGFPE";
    default:
        return "UNKNOWN";
    }
}

static void crash_reraise(int sig)
{
    struct sigaction sa = {};
    sigset_t set;

    sa.sa_handler = SIG_DFL;
    sigemptyset(&sa.sa_mask);
    sigaction(sig, &sa, NULL);

    sigemptyset(&set);
    sigaddset(&set, sig);
    sigprocmask(SIG_UNBLOCK, &set, NULL);

    raise(sig);
    _exit(128 + sig);
}

#ifdef ECO_HAVE_LIBUNWIND
static void crash_print_backtrace(void *ctx)
{
    unw_cursor_t cursor;
    int frame = 0;
    int ret;

#ifdef UNW_INIT_SIGNAL_FRAME
    ret = unw_init_local2(&cursor, (unw_context_t *)ctx, UNW_INIT_SIGNAL_FRAME);
#else
    ret = unw_init_local(&cursor, (unw_context_t *)ctx);
#endif
    if (ret < 0) {
        crash_write("C backtrace unavailable\n");
        return;
    }

    crash_write("C backtrace:\n");

    while (frame < CRASH_MAX_FRAMES) {
        unw_word_t ip = 0;
        unw_word_t sp = 0;
        unw_word_t off = 0;
        char name[256];

        if (unw_get_reg(&cursor, UNW_REG_IP, &ip) < 0)
            break;

        unw_get_reg(&cursor, UNW_REG_SP, &sp);

        crash_write("  #");
        crash_write_dec(frame);
        crash_write(" ip=");
        crash_write_hex((uintptr_t)ip);
        crash_write(" sp=");
        crash_write_hex((uintptr_t)sp);

        if (unw_get_proc_name(&cursor, name, sizeof(name), &off) == 0) {
            crash_write(" ");
            crash_write(name);
            crash_write("+");
            crash_write_hex((uintptr_t)off);
        }

        crash_write("\n");

        ret = unw_step(&cursor);
        if (ret <= 0)
            break;

        frame++;
    }
}
#elif defined(ECO_HAVE_EXECINFO)
static void crash_print_backtrace(void *ctx)
{
    void *frames[CRASH_MAX_FRAMES];
    int nframes;

    (void)ctx;

    crash_write("C backtrace:\n");
    nframes = backtrace(frames, CRASH_MAX_FRAMES);
    backtrace_symbols_fd(frames, nframes, crash_fd);
}
#else
static void crash_print_backtrace(void *ctx)
{
    (void)ctx;
    crash_write("C backtrace unavailable\n");
}
#endif

static void crash_handler(int sig, siginfo_t *si, void *ctx)
{
    if (crash_handling)
        crash_reraise(sig);

    crash_handling = 1;
    crash_open_file();

    crash_write("\n");
    crash_write("fatal signal: ");
    crash_write(crash_signal_name(sig));
    crash_write(" (");
    crash_write_dec(sig);
    crash_write(")");

    if (si && si->si_code > 0 && (sig == SIGSEGV || sig == SIGBUS)) {
        crash_write(" addr=");
        crash_write_hex((uintptr_t)si->si_addr);
    }

    crash_write(" pid=");
    crash_write_dec((long)getpid());
    crash_write("\n");

    crash_print_backtrace(ctx);
    crash_reraise(sig);
}

void eco_crash_backtrace_install(void)
{
    const int signals[] = { SIGSEGV, SIGABRT, SIGBUS, SIGILL, SIGFPE };
    const char *path = getenv("ECO_CRASH_BACKTRACE_FILE");
    struct sigaction sa = {};
    stack_t ss = {};
    size_t i;

    if (path && path[0])
        crash_set_path(path);

    ss.ss_sp = crash_altstack;
    ss.ss_size = sizeof(crash_altstack);
    sigaltstack(&ss, NULL);

    sa.sa_sigaction = crash_handler;
    sigemptyset(&sa.sa_mask);
    sa.sa_flags = SA_SIGINFO | SA_RESETHAND | SA_ONSTACK;

    for (i = 0; i < sizeof(signals) / sizeof(signals[0]); i++)
        sigaction(signals[i], &sa, NULL);
}

#else

void eco_crash_backtrace_install(void)
{
}

#endif
