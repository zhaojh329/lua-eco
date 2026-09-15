#!/usr/bin/env python3
"""Linux PTY integration tests for eco.modbus.rtu.

Usage: python3 tests/modbus-rtu-test.py ECO_EXECUTABLE LUA_MODULE_PREFIX
"""

import os
from pathlib import Path
import pty
import select
import subprocess
import sys
import termios
import time


ROOT = Path(__file__).resolve().parent.parent
HELPER = ROOT / 'tests' / 'modbus-rtu-helper.lua'


def crc16(data):
    crc = 0xFFFF

    for value in data:
        crc ^= value

        for _ in range(8):
            crc = (crc >> 1) ^ 0xA001 if crc & 1 else crc >> 1

    return crc


def make_frame(data):
    crc = crc16(data)
    return data + bytes((crc & 0xFF, crc >> 8))


def read_exact(fd, count, timeout=2):
    result = b''
    deadline = time.monotonic() + timeout

    while len(result) < count:
        left = deadline - time.monotonic()

        if left <= 0 or not select.select([fd], [], [], left)[0]:
            raise AssertionError(
                f'timeout reading {count} bytes; received {result.hex()}')

        result += os.read(fd, count - len(result))

    return result


def check_request(request):
    assert crc16(request[:-2]) == int.from_bytes(request[-2:], 'little')


def valid_response(master, request=None):
    time.sleep(0.02)
    os.write(master, make_frame(b'\x01\x03\x02\x00\x2a'))


def gapped_response(master, request=None):
    time.sleep(0.02)
    response = make_frame(b'\x01\x03\x02\x00\x2a')

    os.write(master, response[:2])
    time.sleep(0.02)

    try:
        os.write(master, response[2:])
    except OSError:
        pass


def echoed_response(master, request):
    os.write(master, request)
    valid_response(master)


def run_case(eco, prefix, action, responder=None, inherited_flags=False):
    master, slave = pty.openpty()
    path = os.ttyname(slave)
    original = termios.tcgetattr(slave)

    if inherited_flags:
        configured = termios.tcgetattr(slave)
        configured[2] |= termios.CRTSCTS
        configured[2] |= getattr(termios, 'CMSPAR', 0)
        termios.tcsetattr(slave, termios.TCSANOW, configured)
        original = configured

    env = os.environ.copy()
    env['LUA_PATH'] = f'{prefix}/?.lua;{prefix}/?/init.lua;;'
    env['LUA_CPATH'] = f'{prefix}/?.so;;'
    proc = subprocess.Popen(
        [eco, str(HELPER), path, action],
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True)

    if action != 'gc':
        request = read_exact(master, 8)
        check_request(request)

        if inherited_flags:
            active = termios.tcgetattr(slave)
            assert active[2] & termios.CRTSCTS == 0
            assert active[2] & termios.CSIZE == termios.CS8

            if getattr(termios, 'CMSPAR', 0):
                assert active[2] & termios.CMSPAR == 0

        if action == 'reconnect':
            request = read_exact(master, 8)
            check_request(request)
            valid_response(master)
        elif responder:
            responder(master, request)

    stdout, stderr = proc.communicate(timeout=3)
    assert proc.returncode == 0, stderr
    assert termios.tcgetattr(slave) == original, \
        f'{action}: serial attributes were not restored'

    os.close(master)
    os.close(slave)

    return stdout.strip()


def main():
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)

    eco = sys.argv[1]
    prefix = sys.argv[2]

    assert run_case(eco, prefix, 'read', valid_response) == 'result\t42\tnil'
    assert run_case(eco, prefix, 'broadcast') == 'result\ttrue\tnil'
    assert 'inter-character timeout' in run_case(
        eco, prefix, 'gap', gapped_response)
    assert run_case(
        eco, prefix, 'flags', valid_response, True) == 'result\t42\tnil'
    assert run_case(eco, prefix, 'echo', echoed_response) == 'result\t42\tnil'
    assert run_case(eco, prefix, 'gc') == 'collected'

    reconnect = run_case(eco, prefix, 'reconnect')
    assert 'first\tserial:' in reconnect
    assert 'queued\tserial: connection changed' in reconnect
    assert 'new\t42\tnil' in reconnect

    print('modbus RTU PTY tests passed')


if __name__ == '__main__':
    main()
