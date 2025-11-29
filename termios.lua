-- SPDX-License-Identifier: MIT
-- Author: Jianhui Zhao <zhaojh329@gmail.com>

--- Terminal I/O settings (termios).
--
-- @module eco.termios
-- @usage
-- local termios = require 'eco.termios'
-- local file = require 'eco.file'
-- local eco = require 'eco'
--
-- local f<close>, err = file.open('/dev/ttyUSB0')
-- assert(f, err)
--
-- local attr, err = termios.tcgetattr(f.fd)
-- assert(attr, err)
--
-- local nattr = attr:clone()
--
-- nattr:clr_flag('l', termios.ECHO)
-- nattr:set_speed(termios.B115200)
--
-- local ok, err = termios.tcsetattr(f.fd, termios.TCSANOW, nattr)
-- assert(ok, err)
--
-- eco.run(function()
--     local data, err = f:read(1024)
--     assert(data, err)
--
--     print('read:', data)
--
--     -- recover term attr
--     termios.tcsetattr(f.fd, termios.TCSANOW, attr)
--
--     eco.unloop()
-- end)
--
-- eco.loop()

local termios = require 'eco.internal.termios'

local M = {
    --- `tcsetattr` action: change attributes immediately.
    TCSANOW = termios.TCSANOW,
    --- `tcsetattr` action: change attributes after transmitting queued output.
    TCSADRAIN = termios.TCSADRAIN,
    --- `tcsetattr` action: flush input and change attributes.
    TCSAFLUSH = termios.TCSAFLUSH,

    --- Input mode flag: ignore BREAK condition.
    IGNBRK = termios.IGNBRK,
    --- Input mode flag: generate SIGINT on BREAK.
    BRKINT = termios.BRKINT,
    --- Input mode flag: ignore framing and parity errors.
    IGNPAR = termios.IGNPAR,
    --- Input mode flag: mark parity errors.
    PARMRK = termios.PARMRK,
    --- Input mode flag: enable input parity checking.
    INPCK = termios.INPCK,
    --- Input mode flag: strip the eighth bit.
    ISTRIP = termios.ISTRIP,
    --- Input mode flag: map NL to CR on input.
    INLCR = termios.INLCR,
    --- Input mode flag: ignore CR on input.
    IGNCR = termios.IGNCR,
    --- Input mode flag: map CR to NL on input.
    ICRNL = termios.ICRNL,
    --- Input mode flag: map uppercase to lowercase on input.
    IUCLC = termios.IUCLC,
    --- Input mode flag: enable XON/XOFF flow control on output.
    IXON = termios.IXON,
    --- Input mode flag: allow any character to restart output.
    IXANY = termios.IXANY,
    --- Input mode flag: enable XON/XOFF flow control on input.
    IXOFF = termios.IXOFF,
    --- Input mode flag: ring bell on input queue full.
    IMAXBEL = termios.IMAXBEL,
    --- Input mode flag: input is UTF-8.
    IUTF8 = termios.IUTF8,

    --- Output mode flag: enable output processing.
    OPOST = termios.OPOST,
    --- Output mode flag: map lowercase to uppercase on output.
    OLCUC = termios.OLCUC,
    --- Output mode flag: map NL to CR-NL on output.
    ONLCR = termios.ONLCR,
    --- Output mode flag: map CR to NL on output.
    OCRNL = termios.OCRNL,
    --- Output mode flag: do not output CR at column 0.
    ONOCR = termios.ONOCR,
    --- Output mode flag: NL performs CR function.
    ONLRET = termios.ONLRET,
    --- Output mode flag: use fill characters for delay.
    OFILL = termios.OFILL,
    --- Output mode flag: fill character is DEL (otherwise NUL).
    OFDEL = termios.OFDEL,
    --- Output delay mask: newline delay.
    NLDLY = termios.NLDLY,
    --- Output delay mask: carriage return delay.
    CRDLY = termios.CRDLY,
    --- Output delay mask: horizontal tab delay.
    TABDLY = termios.TABDLY,
    --- Output delay mask: backspace delay.
    BSDLY = termios.BSDLY,
    --- Output delay mask: vertical tab delay.
    VTDLY = termios.VTDLY,
    --- Output delay mask: form feed delay.
    FFDLY = termios.FFDLY,

    --- Control mode mask: baud rate.
    CBAUD = termios.CBAUD,
    --- Control mode flag/mask: extended baud rates.
    CBAUDEX = termios.CBAUDEX,
    --- Control mode mask: character size.
    CSIZE = termios.CSIZE,
    --- Control mode flag: send two stop bits.
    CSTOPB = termios.CSTOPB,
    --- Control mode flag: enable receiver.
    CREAD = termios.CREAD,
    --- Control mode flag: enable parity generation and detection.
    PARENB = termios.PARENB,
    --- Control mode flag: odd parity.
    PARODD = termios.PARODD,
    --- Control mode flag: lower modem control lines on last close.
    HUPCL = termios.HUPCL,
    --- Control mode flag: ignore modem control lines.
    CLOCAL = termios.CLOCAL,
    --- Control mode mask: input baud rate.
    CIBAUD = termios.CIBAUD,
    --- Control mode flag: stick parity.
    CMSPAR = termios.CMSPAR,
    --- Control mode flag: RTS/CTS hardware flow control.
    CRTSCTS = termios.CRTSCTS,

    --- Local mode flag: enable signals (INTR/QUIT/SUSP).
    ISIG = termios.ISIG,
    --- Local mode flag: canonical input (line buffering).
    ICANON = termios.ICANON,
    --- Local mode flag: enable special character processing (XCASE).
    XCASE = termios.XCASE,
    --- Local mode flag: echo input characters.
    ECHO = termios.ECHO,
    --- Local mode flag: echo ERASE as backspace-space-backspace.
    ECHOE = termios.ECHOE,
    --- Local mode flag: echo NL after KILL.
    ECHOK = termios.ECHOK,
    --- Local mode flag: echo NL even if ECHO is off.
    ECHONL = termios.ECHONL,
    --- Local mode flag: echo control characters as ^X.
    ECHOCTL = termios.ECHOCTL,
    --- Local mode flag: echo erased characters.
    ECHOPRT = termios.ECHOPRT,
    --- Local mode flag: visual erase for line kill.
    ECHOKE = termios.ECHOKE,
    --- Local mode flag: output being flushed.
    FLUSHO = termios.FLUSHO,
    --- Local mode flag: disable flush after interrupt/suspend.
    NOFLSH = termios.NOFLSH,
    --- Local mode flag: send SIGTTOU for background output.
    TOSTOP = termios.TOSTOP,
    --- Local mode flag: reprint pending input at next read.
    PENDIN = termios.PENDIN,
    --- Local mode flag: enable implementation-defined input processing.
    IEXTEN = termios.IEXTEN,

    --- Control character index: discard (VDSUSP/VDISCARD).
    VDISCARD = termios.VDISCARD,
    --- Control character index: EOF.
    VEOF = termios.VEOF,
    --- Control character index: EOL.
    VEOL = termios.VEOL,
    --- Control character index: EOL2.
    VEOL2 = termios.VEOL2,
    --- Control character index: ERASE.
    VERASE = termios.VERASE,
    --- Control character index: INTR.
    VINTR = termios.VINTR,
    --- Control character index: KILL.
    VKILL = termios.VKILL,
    --- Control character index: literal next (LNEXT).
    VLNEXT = termios.VLNEXT,
    --- Control character index: minimum number of bytes for noncanonical read.
    VMIN = termios.VMIN,
    --- Control character index: QUIT.
    VQUIT = termios.VQUIT,
    --- Control character index: REPRINT.
    VREPRINT = termios.VREPRINT,
    --- Control character index: START (XON).
    VSTART = termios.VSTART,
    --- Control character index: STOP (XOFF).
    VSTOP = termios.VSTOP,
    --- Control character index: SUSP.
    VSUSP = termios.VSUSP,
    --- Control character index: timeout in deciseconds for noncanonical read.
    VTIME = termios.VTIME,
    --- Control character index: word erase.
    VWERASE = termios.VWERASE,

    --- Baud rate constant: hang up.
    B0 = termios.B0,
    --- Baud rate constant: 50.
    B50 = termios.B50,
    --- Baud rate constant: 75.
    B75 = termios.B75,
    --- Baud rate constant: 110.
    B110 = termios.B110,
    --- Baud rate constant: 134.
    B134 = termios.B134,
    --- Baud rate constant: 150.
    B150 = termios.B150,
    --- Baud rate constant: 200.
    B200 = termios.B200,
    --- Baud rate constant: 300.
    B300 = termios.B300,
    --- Baud rate constant: 600.
    B600 = termios.B600,
    --- Baud rate constant: 1200.
    B1200 = termios.B1200,
    --- Baud rate constant: 1800.
    B1800 = termios.B1800,
    --- Baud rate constant: 2400.
    B2400 = termios.B2400,
    --- Baud rate constant: 4800.
    B4800 = termios.B4800,
    --- Baud rate constant: 9600.
    B9600 = termios.B9600,
    --- Baud rate constant: 19200.
    B19200 = termios.B19200,
    --- Baud rate constant: 38400.
    B38400 = termios.B38400,
    --- Baud rate constant: 57600.
    B57600 = termios.B57600,
    --- Baud rate constant: 115200.
    B115200 = termios.B115200,
    --- Baud rate constant: 230400.
    B230400 = termios.B230400,

    --- `tcflush` selector: flush input queue.
    TCIFLUSH = termios.TCIFLUSH,
    --- `tcflush` selector: flush output queue.
    TCOFLUSH = termios.TCOFLUSH,
    --- `tcflush` selector: flush both input and output queues.
    TCIOFLUSH = termios.TCIOFLUSH,

    --- `tcflow` action: suspend output.
    TCOOFF = termios.TCOOFF,
    --- `tcflow` action: restart output.
    TCOON = termios.TCOON,
    --- `tcflow` action: transmit STOP character (XOFF).
    TCIOFF = termios.TCIOFF,
    --- `tcflow` action: transmit START character (XON).
    TCION = termios.TCION,
}

return setmetatable(M, { __index = termios })
