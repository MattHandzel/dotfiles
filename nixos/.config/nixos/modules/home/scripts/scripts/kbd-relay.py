#!/usr/bin/env python3
"""Relay a hot-plugged keyboard through a virtual keyboard that always exists.

Wispr Flow enumerates evdev keyboards ONCE at startup and never watches udev, so
a keyboard connected later (the Bluetooth TOTEM) is invisible to it forever — its
hotkey simply does nothing. Restarting Wispr to force a rescan is not acceptable:
it could be mid-recording.

So instead of making Wispr notice a new device, we make sure the device it is
already watching never goes away. This creates one uinput keyboard at login —
before Wispr starts, and it never disappears — grabs the real keyboard whenever
it connects, and forwards its events verbatim.

Verbatim is the point. An earlier attempt routed the TOTEM through kanata, whose
layer/chord engine mangled keys the firmware had already remapped. This relay
does no remapping of any kind: an event in is the same event out.

The grab (EVIOCGRAB) is what stops the compositor seeing every keypress twice —
once from the real device and once from the relay. If this process dies the grab
dies with it and the keyboard falls straight back to working normally, so the
worst case is Wispr stops seeing it, never a dead keyboard.
"""
import errno
import fcntl
import glob
import os
import select
import struct
import sys
import time

EV_SYN, EV_KEY, EV_MSC = 0x00, 0x01, 0x04
UI, E = ord("U"), ord("E")
INPUT_EVENT = struct.Struct("llHHi")

# Keyboards to relay, by exact evdev name. Bluetooth devices get a new event
# number on every reconnect, so the name is the only stable handle.
# ZMK firmware reports the TOTEM as "ZMK Project Matt's TOTEM Keyboard"; the older
# short name is kept as an alias. Baked in as the default because a systemd
# Environment= value can't hold spaces/apostrophes without being word-split
# (that silently reduced this to watching for "ZMK" — a device that never exists).
_DEFAULT = "ZMK Project Matt's TOTEM Keyboard|Matt's TOTEM Keyboard"
TARGETS = [n for n in os.environ.get("RELAY_KEYBOARDS", _DEFAULT).split("|") if n]

RESCAN_SECONDS = 2.0


def _iow(nr, size):
    return (1 << 30) | (size << 16) | (UI << 8) | nr


def _io(nr):
    return (UI << 8) | nr


def _ior(nr, size):
    return (2 << 30) | (size << 16) | (E << 8) | nr


UI_SET_EVBIT, UI_SET_KEYBIT = _iow(100, 4), _iow(101, 4)
UI_DEV_CREATE, UI_DEV_DESTROY = _io(1), _io(2)
EVIOCGNAME = _ior(0x06, 256)
EVIOCGKEY = _ior(0x18, 32)
EVIOCGRAB = (1 << 30) | (4 << 16) | (E << 8) | 0x90


def log(msg):
    print(msg, file=sys.stderr, flush=True)


def make_relay():
    """One virtual keyboard declaring every keyboard keycode (1-255), which
    covers everything the TOTEM emits — media and brightness keys included, as
    those all sit below 256.

    Nothing at or above 256 is declared. That range is BTN_* (mouse buttons,
    BTN_DPAD, BTN_TRIGGER_HAPPY, ...), and declaring any of it makes the kernel
    class this device as a joystick and hang a js* handler off it instead of
    treating it as a plain keyboard."""
    fd = os.open("/dev/uinput", os.O_WRONLY | os.O_NONBLOCK)
    fcntl.ioctl(fd, UI_SET_EVBIT, EV_KEY)
    fcntl.ioctl(fd, UI_SET_EVBIT, EV_MSC)
    for code in range(1, 256):
        fcntl.ioctl(fd, UI_SET_KEYBIT, code)
    os.write(fd, struct.pack("<80sHHHHI256i", b"Keyboard Relay", 0x03, 0x1D50, 0x615E, 1, 0, *([0] * 256)))
    fcntl.ioctl(fd, UI_DEV_CREATE)
    return fd


def find(name):
    for path in glob.glob("/dev/input/event*"):
        try:
            fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
        except OSError:
            continue
        try:
            if fcntl.ioctl(fd, EVIOCGNAME, bytes(256)).split(b"\x00")[0].decode(errors="replace") == name:
                return path
        except OSError:
            pass
        finally:
            os.close(fd)
    return None


def held_keys(fd):
    bits = fcntl.ioctl(fd, EVIOCGKEY, bytes(32))
    return [k for k in range(1, 256) if bits[k // 8] >> (k % 8) & 1]


def main():
    relay = make_relay()
    log(f"relay keyboard created; watching for {TARGETS}")
    grabbed = {}  # name -> (path, fd)
    last_scan = 0.0

    while True:
        now = time.monotonic()
        if now - last_scan >= RESCAN_SECONDS:
            last_scan = now
            for name in TARGETS:
                if name in grabbed:
                    continue
                path = find(name)
                if not path:
                    continue
                try:
                    fd = os.open(path, os.O_RDONLY)
                    fcntl.ioctl(fd, EVIOCGRAB, 1)
                except OSError as e:
                    # Something else holds it (a stale kanata grab, say). Try again later.
                    log(f"cannot grab {name} at {path}: {e}")
                    try:
                        os.close(fd)
                    except Exception:
                        pass
                    continue
                grabbed[name] = (path, fd)
                log(f"grabbed {name} ({path}) — relaying")

        if not grabbed:
            time.sleep(0.2)
            continue

        fds = [fd for _, fd in grabbed.values()]
        ready, _, _ = select.select(fds, [], [], 0.5)
        for fd in ready:
            name = next(n for n, (_, f) in grabbed.items() if f == fd)
            try:
                data = os.read(fd, INPUT_EVENT.size * 64)
            except (BlockingIOError, InterruptedError):
                continue
            except OSError as e:
                if e.errno in (errno.ENODEV, errno.EBADF):
                    # Keyboard disconnected. Release anything it left held, or the
                    # modifier stays stuck on the relay device forever.
                    for code in held_keys_safe(relay):
                        os.write(relay, INPUT_EVENT.pack(0, 0, EV_KEY, code, 0))
                    os.write(relay, INPUT_EVENT.pack(0, 0, EV_SYN, 0, 0))
                    os.close(fd)
                    grabbed.pop(name, None)
                    log(f"{name} disconnected — released its keys, waiting for it to come back")
                    continue
                raise
            # Verbatim forward. No remapping, ever.
            for i in range(0, len(data), INPUT_EVENT.size):
                _, _, etype, code, value = INPUT_EVENT.unpack(data[i : i + INPUT_EVENT.size])
                if etype in (EV_KEY, EV_MSC, EV_SYN):
                    os.write(relay, INPUT_EVENT.pack(0, 0, etype, code, value))


def held_keys_safe(relay_fd):
    """Keys the relay currently reports as down. The relay is write-only from
    our side, so read the state back from its own /dev/input node."""
    path = find("Keyboard Relay")
    if not path:
        return []
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
    except OSError:
        return []
    try:
        return held_keys(fd)
    except OSError:
        return []
    finally:
        os.close(fd)


if __name__ == "__main__":
    main()
