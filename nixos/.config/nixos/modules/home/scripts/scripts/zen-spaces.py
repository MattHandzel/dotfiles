#!/usr/bin/env python3
"""Read/write Zen Browser spaces stored in a mozLz4 session file.

Subcommands:
  verify  <session>            round-trip decode->encode->decode, prove losslessness
  list    <session>            print current spaces
  add     <session> <spec.json> [--out PATH]
                               add spaces (idempotent by name), write result
"""
import argparse
import json
import os
import shutil
import sys
import uuid
from pathlib import Path

import lz4.block

MAGIC = b"mozLz40\0"


def read_mozlz4(path):
    with open(path, "rb") as fh:
        magic = fh.read(8)
        if not magic.startswith(b"mozLz4"):
            raise SystemExit(f"not a mozLz4 file: {magic!r}")
        size = int.from_bytes(fh.read(4), "little")
        raw = lz4.block.decompress(fh.read(), uncompressed_size=size)
    return json.loads(raw), raw


def write_mozlz4(path, obj):
    raw = json.dumps(obj, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    comp = lz4.block.compress(raw, store_size=False)
    with open(path, "wb") as fh:
        fh.write(MAGIC)
        fh.write(len(raw).to_bytes(4, "little"))
        fh.write(comp)


def spaces_of(data):
    key = "spaces" if "spaces" in data else "workspaces"
    return key, data.setdefault(key, [])


def cmd_verify(args):
    data, raw = read_mozlz4(args.session)
    tmp = args.session + ".roundtrip"
    write_mozlz4(tmp, data)
    data2, raw2 = read_mozlz4(tmp)
    ok_json = data == data2
    key, sp = spaces_of(data)
    key2, sp2 = spaces_of(data2)
    print(f"decode->encode->decode json equal : {ok_json}")
    print(f"spaces preserved                  : {len(sp)} -> {len(sp2)}")
    print(f"tabs preserved                    : "
          f"{len(data.get('tabs', []))} -> {len(data2.get('tabs', []))}")
    print(f"original raw bytes                : {len(raw)}")
    print(f"round-tripped raw bytes           : {len(raw2)}")
    sys.exit(0 if ok_json else 1)


def cmd_list(args):
    data, _ = read_mozlz4(args.session)
    _, sp = spaces_of(data)
    for s in sp:
        print(f"{s.get('icon', ' '):<3} {s.get('name', '?'):<24} "
              f"container={s.get('containerTabId', '-')} uuid={s['uuid']}")



def _refuse_if_profile_in_use(session_path):
    """Zen rewrites zen-sessions.jsonlz4 from memory every few seconds and again on
    exit, so an edit made while it runs is silently clobbered — the write appears to
    succeed and then vanishes.

    Detect via the profile's own `lock` symlink (-> "127.0.0.2:+<pid>"), not the
    process name: Zen's comm is truncated to ".zen-beta-wrapp", so `pgrep -x
    zen-beta` silently never matches. The lock is per-profile, which is the right
    granularity, and it cannot accidentally match this script's own command line.
    """
    prof = Path(session_path).resolve().parent
    lock = prof / "lock"
    if not lock.is_symlink():
        return                                  # not running
    target = os.readlink(lock)                  # e.g. "127.0.0.2:+5670"
    pid = target.rpartition("+")[2].strip()
    if pid.isdigit() and Path(f"/proc/{pid}").exists():
        sys.exit(
            f"REFUSING: profile {prof.name} is in use by Zen (pid {pid}).\n"
            f"Quit Zen completely, then re-run — otherwise Zen overwrites this file "
            f"from memory and your new spaces disappear."
        )


def cmd_add(args):
    _refuse_if_profile_in_use(args.session)
    data, _ = read_mozlz4(args.session)
    key, sp = spaces_of(data)
    existing = {s.get("name") for s in sp}
    spec = json.loads(open(args.spec).read())

    added = []
    for want in spec["spaces"]:
        if want["name"] in existing:
            print(f"  = {want['name']!r} already exists, skipping")
            continue
        sp.append({
            "uuid": "{%s}" % uuid.uuid4(),
            "name": want["name"],
            "icon": want.get("icon", "�"),
            "theme": {"type": "gradient", "gradientColors": [],
                      "opacity": 0.5, "texture": 0},
            "containerTabId": want.get("containerTabId", 0),
            "hasCollapsedPinnedTabs": False,
        })
        added.append(want["name"])
        print(f"  + {want['name']!r} added")

    out = args.out or args.session
    if out == args.session:
        shutil.copy2(args.session, args.session + ".bak")
        print(f"  backup -> {args.session}.bak")
    write_mozlz4(out, data)
    print(f"wrote {out} ({len(sp)} spaces total, {len(added)} new)")


p = argparse.ArgumentParser()
sub = p.add_subparsers(dest="cmd", required=True)
v = sub.add_parser("verify"); v.add_argument("session"); v.set_defaults(fn=cmd_verify)
l = sub.add_parser("list"); l.add_argument("session"); l.set_defaults(fn=cmd_list)
a = sub.add_parser("add"); a.add_argument("session"); a.add_argument("spec")
a.add_argument("--out"); a.set_defaults(fn=cmd_add)
args = p.parse_args()
args.fn(args)
