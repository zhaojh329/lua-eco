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

#include <stdbool.h>
#include <termios.h>
#include <errno.h>

#include "eco.h"

#define ECO_TERMIOS_ATTR_MT "eco{termios}"


static int lua_termios_change_flag(lua_State *L, bool set)
{
    struct termios *attr = luaL_checkudata(L, 1, ECO_TERMIOS_ATTR_MT);
    const char *type = luaL_checkstring(L, 2);
    int flag = luaL_checkinteger(L, 3);
    tcflag_t *flags;

    switch (type[0]) {
    case 'i':
        flags = &attr->c_iflag;
        break;
    case 'o':
        flags = &attr->c_oflag;
        break;
    case 'c':
        flags = &attr->c_cflag;
        break;
    case 'l':
        flags = &attr->c_lflag;
        break;
    default:
        luaL_argerror(L, 2, "invalid type");
        return 0;
    }

    if (set)
        *flags |= flag;
    else
        *flags &= ~flag;

    return 0;
}

static int lua_termios_attr_set_flag(lua_State *L)
{
    return lua_termios_change_flag(L, true);
}

static int lua_termios_attr_clr_flag(lua_State *L)
{
    return lua_termios_change_flag(L, false);
}

static int lua_termios_attr_set_cc(lua_State *L)
{
    struct termios *attr = luaL_checkudata(L, 1, ECO_TERMIOS_ATTR_MT);
    int name = luaL_checkinteger(L, 2);
    int value = luaL_checkinteger(L, 3);

    if (name < 0 || name >= NCCS)
        luaL_argerror(L, 2, "invalid cc name");

    attr->c_cc[name] = value;
    return 0;
}

static int lua_termios_attr_get_speed_common(lua_State *L, speed_t (*get)(const struct termios *))
{
    struct termios *attr = luaL_checkudata(L, 1, ECO_TERMIOS_ATTR_MT);
    lua_pushinteger(L, get(attr));
    return 1;
}

static int lua_termios_attr_get_ispeed(lua_State *L)
{
    return lua_termios_attr_get_speed_common(L, cfgetispeed);
}

static int lua_termios_attr_get_ospeed(lua_State *L)
{
    return lua_termios_attr_get_speed_common(L, cfgetospeed);
}

static int lua_termios_attr_set_speed_common(lua_State *L, int (*set)(struct termios *, speed_t))
{
    struct termios *attr = luaL_checkudata(L, 1, ECO_TERMIOS_ATTR_MT);
    int speed = luaL_checkinteger(L, 2);

    if (set(attr, speed)) {
        lua_pushboolean(L, false);
        lua_pushstring(L, strerror(errno));
        return 2;
    }

    lua_pushboolean(L, true);
    return 1;
}

static int lua_termios_attr_set_ispeed(lua_State *L)
{
    return lua_termios_attr_set_speed_common(L, cfsetispeed);
}

static int lua_termios_attr_set_ospeed(lua_State *L)
{
    return lua_termios_attr_set_speed_common(L, cfsetospeed);
}

static int lua_termios_attr_set_speed(lua_State *L)
{
    return lua_termios_attr_set_speed_common(L, cfsetspeed);
}

static int lua_termios_attr_clone(lua_State *L)
{
    struct termios *attr = luaL_checkudata(L, 1, ECO_TERMIOS_ATTR_MT);
    struct termios *nattr = lua_newuserdata(L, sizeof(struct termios));

    luaL_getmetatable(L, ECO_TERMIOS_ATTR_MT);
    lua_setmetatable(L, -2);

    memcpy(nattr, attr, sizeof(struct termios));

    return 1;
}

static const struct luaL_Reg termios_methods[] =  {
    {"set_flag", lua_termios_attr_set_flag},
    {"clr_flag", lua_termios_attr_clr_flag},
    {"set_cc", lua_termios_attr_set_cc},
    {"get_ispeed", lua_termios_attr_get_ispeed},
    {"get_ospeed", lua_termios_attr_get_ospeed},
    {"set_ispeed", lua_termios_attr_set_ispeed},
    {"set_ospeed", lua_termios_attr_set_ospeed},
    {"set_speed", lua_termios_attr_set_speed},
    {"clone", lua_termios_attr_clone},
    {NULL, NULL}
};

static int lua_tcgetattr(lua_State *L)
{
    int fd = luaL_checkinteger(L, 1);
    struct termios *attr = lua_newuserdata(L, sizeof(struct termios));

    if (tcgetattr(fd, attr)) {
        lua_pushnil(L);
        lua_pushstring(L, strerror(errno));
        return 2;
    }

    eco_new_metatable(L, ECO_TERMIOS_ATTR_MT, termios_methods);
    lua_setmetatable(L, -2);

    return 1;
}

static int lua_tcsetattr(lua_State *L)
{
    int fd = luaL_checkinteger(L, 1);
    int actions = luaL_checkinteger(L, 2);
    struct termios *attr = luaL_checkudata(L, 3, ECO_TERMIOS_ATTR_MT);

    if (tcsetattr(fd, actions, attr)) {
        lua_pushboolean(L, false);
        lua_pushstring(L, strerror(errno));
        return 2;
    }

    lua_pushboolean(L, true);
    return 1;
}

static int lua_tcflush(lua_State *L)
{
    int fd = luaL_checkinteger(L, 1);
    int queue_selector = luaL_checkinteger(L, 2);

    if (tcflush(fd, queue_selector)) {
        lua_pushboolean(L, false);
        lua_pushstring(L, strerror(errno));
        return 2;
    }

    lua_pushboolean(L, true);
    return 1;
}

static int lua_tcflow(lua_State *L)
{
    int fd = luaL_checkinteger(L, 1);
    int action = luaL_checkinteger(L, 2);

    if (tcflow(fd, action)) {
        lua_pushboolean(L, false);
        lua_pushstring(L, strerror(errno));
        return 2;
    }

    lua_pushboolean(L, true);
    return 1;
}

int luaopen_eco_core_termios(lua_State *L)
{
    lua_newtable(L);

    /* actions for tcsetattr */
    lua_add_constant(L, "TCSANOW", TCSANOW);
    lua_add_constant(L, "TCSADRAIN", TCSADRAIN);
    lua_add_constant(L, "TCSAFLUSH", TCSAFLUSH);

    /* iflag */
    lua_add_constant(L, "IGNBRK", IGNBRK);
    lua_add_constant(L, "BRKINT", BRKINT);
    lua_add_constant(L, "IGNPAR", IGNPAR);
    lua_add_constant(L, "PARMRK", PARMRK);
    lua_add_constant(L, "INPCK", INPCK);
    lua_add_constant(L, "ISTRIP", ISTRIP);
    lua_add_constant(L, "INLCR", INLCR);
    lua_add_constant(L, "IGNCR", IGNCR);
    lua_add_constant(L, "ICRNL", ICRNL);
    lua_add_constant(L, "IUCLC", IUCLC);
    lua_add_constant(L, "IXON", IXON);
    lua_add_constant(L, "IXANY", IXANY);
    lua_add_constant(L, "IXOFF", IXOFF);
    lua_add_constant(L, "IMAXBEL", IMAXBEL);
    lua_add_constant(L, "IUTF8", IUTF8);

    /* oflag */
    lua_add_constant(L, "OPOST", OPOST);
    lua_add_constant(L, "OLCUC", OLCUC);
    lua_add_constant(L, "ONLCR", ONLCR);
    lua_add_constant(L, "OCRNL", OCRNL);
    lua_add_constant(L, "ONOCR", ONOCR);
    lua_add_constant(L, "ONLRET", ONLRET);
    lua_add_constant(L, "OFILL", OFILL);
    lua_add_constant(L, "OFDEL", OFDEL);
    lua_add_constant(L, "NLDLY", NLDLY);
    lua_add_constant(L, "CRDLY", CRDLY);
    lua_add_constant(L, "TABDLY", TABDLY);
    lua_add_constant(L, "BSDLY", BSDLY);
    lua_add_constant(L, "VTDLY", VTDLY);
    lua_add_constant(L, "FFDLY", FFDLY);

    /* cflag */
    lua_add_constant(L, "CBAUD", CBAUD);
    lua_add_constant(L, "CBAUDEX", CBAUDEX);
    lua_add_constant(L, "CSIZE", CSIZE);
    lua_add_constant(L, "CSTOPB", CSTOPB);
    lua_add_constant(L, "CREAD", CREAD);
    lua_add_constant(L, "PARENB", PARENB);
    lua_add_constant(L, "PARODD", PARODD);
    lua_add_constant(L, "HUPCL", HUPCL);
    lua_add_constant(L, "CLOCAL", CLOCAL);
    lua_add_constant(L, "CIBAUD", CIBAUD);
    lua_add_constant(L, "CMSPAR", CMSPAR);
    lua_add_constant(L, "CRTSCTS", CRTSCTS);

    /* lflag */
    lua_add_constant(L, "ISIG", ISIG);
    lua_add_constant(L, "ICANON", ICANON);
    lua_add_constant(L, "XCASE", XCASE);
    lua_add_constant(L, "ECHO", ECHO);
    lua_add_constant(L, "ECHOE", ECHOE);
    lua_add_constant(L, "ECHOK", ECHOK);
    lua_add_constant(L, "ECHONL", ECHONL);
    lua_add_constant(L, "ECHOCTL", ECHOCTL);
    lua_add_constant(L, "ECHOPRT", ECHOPRT);
    lua_add_constant(L, "ECHOKE", ECHOKE);
    lua_add_constant(L, "FLUSHO", FLUSHO);
    lua_add_constant(L, "NOFLSH", NOFLSH);
    lua_add_constant(L, "TOSTOP", TOSTOP);
    lua_add_constant(L, "PENDIN", PENDIN);
    lua_add_constant(L, "IEXTEN", IEXTEN);

    /* cc */
    lua_add_constant(L, "VDISCARD", VDISCARD);
    lua_add_constant(L, "VEOF", VEOF);
    lua_add_constant(L, "VEOL", VEOL);
    lua_add_constant(L, "VEOL2", VEOL2);
    lua_add_constant(L, "VERASE", VERASE);
    lua_add_constant(L, "VINTR", VINTR);
    lua_add_constant(L, "VKILL", VKILL);
    lua_add_constant(L, "VLNEXT", VLNEXT);
    lua_add_constant(L, "VMIN", VMIN);
    lua_add_constant(L, "VQUIT", VQUIT);
    lua_add_constant(L, "VREPRINT", VREPRINT);
    lua_add_constant(L, "VSTART", VSTART);
    lua_add_constant(L, "VSTOP", VSTOP);
    lua_add_constant(L, "VSUSP", VSUSP);
    lua_add_constant(L, "VTIME", VTIME);
    lua_add_constant(L, "VWERASE", VWERASE);

    /* speed */
    lua_add_constant(L, "B0", B0);
    lua_add_constant(L, "B50", B50);
    lua_add_constant(L, "B75", B75);
    lua_add_constant(L, "B110", B110);
    lua_add_constant(L, "B134", B134);
    lua_add_constant(L, "B150", B150);
    lua_add_constant(L, "B200", B200);
    lua_add_constant(L, "B300", B300);
    lua_add_constant(L, "B600", B600);
    lua_add_constant(L, "B1200", B1200);
    lua_add_constant(L, "B1800", B1800);
    lua_add_constant(L, "B2400", B2400);
    lua_add_constant(L, "B4800", B4800);
    lua_add_constant(L, "B9600", B9600);
    lua_add_constant(L, "B19200", B19200);
    lua_add_constant(L, "B38400", B38400);
    lua_add_constant(L, "B57600", B57600);
    lua_add_constant(L, "B115200", B115200);
    lua_add_constant(L, "B230400", B230400);

    /* queue_selector for tcflush */
    lua_add_constant(L, "TCIFLUSH", TCIFLUSH);
    lua_add_constant(L, "TCOFLUSH", TCOFLUSH);
    lua_add_constant(L, "TCIOFLUSH", TCIOFLUSH);

    /* action for tcflow */
    lua_add_constant(L, "TCOOFF", TCOOFF);
    lua_add_constant(L, "TCOON", TCOON);
    lua_add_constant(L, "TCIOFF", TCIOFF);
    lua_add_constant(L, "TCION", TCION);

    lua_pushcfunction(L, lua_tcgetattr);
    lua_setfield(L, -2, "tcgetattr");

    lua_pushcfunction(L, lua_tcsetattr);
    lua_setfield(L, -2, "tcsetattr");

    lua_pushcfunction(L, lua_tcflush);
    lua_setfield(L, -2, "tcflush");

    lua_pushcfunction(L, lua_tcflow);
    lua_setfield(L, -2, "tcflow");

    return 1;
}
