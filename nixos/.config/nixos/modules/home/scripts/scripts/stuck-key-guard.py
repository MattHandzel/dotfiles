#!/usr/bin/env python3
"""Force-release keys left stranded on virtual (uinput) keyboards.

Wispr Flow types by pressing a modifier, emitting characters, then releasing it
("Wispr Flow Linux Helper" is a uinput keyboard). If that burst is interrupted
the release is never sent: the key stays logically down on the *device*, the
compositor latches the modifier, and everything behaves as though Shift/Super/
Ctrl is held until something else happens to press and release that key. The
same trap catches any synthetic typist (ydotool, macro tools, kanata).

Nothing is physically stuck, so nothing physical can un-stick it. The fix is to
inject the missing key-up straight into the offending device node: the kernel's
input_inject_event() path updates that device's key state *and* delivers the
release to libinput, which clears the compositor.

Safety rests on one asymmetry: a human cannot hold a key on a synthetic device.
So a key held on a virtual keyboard, with the device gone quiet and no physical
key down anywhere, is always a bug — never a person leaning on Shift. Physical
keyboards are only ever read, never injected into, and a key held on one blocks
all releases (this is what makes kanata's home-row mods safe: those hold a
modifier precisely while a real key is down; EVIOCGKEY still reports that state
even though kanata holds the device with an exclusive EVIOCGRAB).
"""
import errno
import fcntl
import glob
import os
import struct
import subprocess
import sys
import time

EV_SYN, EV_KEY = 0x00, 0x01
# Keycodes 1..255 are keyboard keys; BTN_* (mouse, gamepad) start at 256 and are
# deliberately out of range, so a held mouse button can never block a release.
KEY_COUNT = 256
KEY_BYTES = KEY_COUNT // 8
INPUT_EVENT = struct.Struct("llHHi")

POLL_SECONDS = 0.2
RESCAN_SECONDS = 2.0
# How long a virtual keyboard must sit silent with a key still down before we
# call it stuck. Comfortably longer than the gap between keystrokes of a
# synthetic typist mid-burst, so we never cut a modifier out of live dictation.
IDLE_SECONDS = float(os.environ.get("STUCK_KEY_IDLE_SECONDS", "1.0"))

KEY_NAMES = {
    29: "Ctrl", 42: "Shift", 54: "RightShift", 56: "Alt",
    58: "CapsLock", 97: "RightCtrl", 100: "AltGr", 125: "Super", 126: "RightSuper",
}


def _ior(nr, size):
    return (2 << 30) | (size << 16) | (ord("E") << 8) | nr


EVIOCGNAME = _ior(0x06, 256)
EVIOCGBIT_EV = _ior(0x20, 8)
EVIOCGKEY = _ior(0x18, KEY_BYTES)


def key_name(code):
    return KEY_NAMES.get(code, f"key {code}")


def log(msg):
    print(msg, file=sys.stderr, flush=True)


class Keyboard:
    def __init__(self, path, fd, name, virtual):
        self.path, self.fd, self.name, self.virtual = path, fd, name, virtual
        self.quiet_since = time.monotonic()
        self.held = frozenset()

    def held_keys(self):
        """Authoritative key state, straight from the kernel. Works even on a
        device another process holds with an exclusive grab."""
        bits = fcntl.ioctl(self.fd, EVIOCGKEY, bytes(KEY_BYTES))
        return frozenset(k for k in range(1, KEY_COUNT) if bits[k // 8] >> (k % 8) & 1)

    def drain(self):
        """Consume pending events purely to detect activity. Every evdev reader
        gets its own copy of the stream, so this takes nothing from Hyprland."""
        seen = False
        while True:
            try:
                if not os.read(self.fd, INPUT_EVENT.size * 64):
                    break
                seen = True
            except BlockingIOError:
                break
        return seen

    def release(self, keys):
        for code in sorted(keys):
            os.write(self.fd, INPUT_EVENT.pack(0, 0, EV_KEY, code, 0))
        os.write(self.fd, INPUT_EVENT.pack(0, 0, EV_SYN, 0, 0))


def is_keyboard(fd):
    types = fcntl.ioctl(fd, EVIOCGBIT_EV, bytes(8))
    if not types[EV_KEY // 8] >> (EV_KEY % 8) & 1:
        return False
    # Require letter keys, so power buttons, lid switches and other
    # single-purpose EV_KEY devices are not mistaken for keyboards.
    bits = fcntl.ioctl(fd, _ior(0x20 + EV_KEY, KEY_BYTES), bytes(KEY_BYTES))
    return all(bits[k // 8] >> (k % 8) & 1 for k in (16, 30, 44))  # Q, A, Z


def scan():
    """Open every keyboard. Virtual devices are opened read-write because they
    are the only ones we ever inject into."""
    found = {}
    for path in sorted(glob.glob("/dev/input/event*")):
        # uinput-created devices live under /sys/devices/virtual, whatever bus
        # they claim to be (Wispr's helper dishonestly reports itself as USB).
        sysfs = os.path.realpath(f"/sys/class/input/{os.path.basename(path)}")
        virtual = sysfs.startswith("/sys/devices/virtual/")
        flags = (os.O_RDWR if virtual else os.O_RDONLY) | os.O_NONBLOCK
        try:
            fd = os.open(path, flags)
        except OSError:
            continue
        try:
            if not is_keyboard(fd):
                os.close(fd)
                continue
            name = fcntl.ioctl(fd, EVIOCGNAME, bytes(256)).split(b"\x00")[0].decode(errors="replace")
        except OSError:
            os.close(fd)
            continue
        found[path] = Keyboard(path, fd, name, virtual)
    return found


def unstick(kbd, keys, reason):
    pretty = ", ".join(key_name(k) for k in sorted(keys))
    log(f"releasing stuck {pretty} on virtual keyboard '{kbd.name}' ({reason})")
    kbd.release(keys)
    subprocess.run(
        ["notify-send", "-u", "normal", "-i", "input-keyboard",
         "Released stuck key", f"{pretty} was stuck on {kbd.name}"],
        check=False,
    )


def main():
    force_now = "--now" in sys.argv[1:]
    devices = {}
    last_scan = 0.0

    while True:
        now = time.monotonic()
        if now - last_scan >= RESCAN_SECONDS:
            fresh = scan()
            for path, kbd in list(devices.items()):
                if path not in fresh:
                    os.close(kbd.fd)
                    devices.pop(path)
            for path, kbd in fresh.items():
                if path in devices:
                    os.close(kbd.fd)
                else:
                    devices[path] = kbd
            last_scan = now

        physical_down = False
        virtual = []
        for kbd in list(devices.values()):
            try:
                busy = kbd.drain()
                held = kbd.held_keys()
            except OSError as e:
                if e.errno in (errno.ENODEV, errno.EBADF):
                    os.close(kbd.fd)
                    devices.pop(kbd.path, None)
                    continue
                raise
            if kbd.virtual:
                if busy or held != kbd.held:
                    kbd.quiet_since = now
                kbd.held = held
                virtual.append(kbd)
            elif held:
                physical_down = True

        for kbd in virtual:
            if not kbd.held:
                continue
            if force_now:
                unstick(kbd, kbd.held, "manual --now")
                continue
            # A physical key being down means a human is mid-chord: whatever this
            # virtual device is asserting is very likely a deliberate consequence
            # of that (a kanata home-row mod), so leave it alone.
            if physical_down:
                continue
            if now - kbd.quiet_since >= IDLE_SECONDS:
                unstick(kbd, kbd.held, f"held with no activity for {IDLE_SECONDS:g}s")
                kbd.quiet_since = now

        if force_now:
            return
        time.sleep(POLL_SECONDS)


if __name__ == "__main__":
    main()
