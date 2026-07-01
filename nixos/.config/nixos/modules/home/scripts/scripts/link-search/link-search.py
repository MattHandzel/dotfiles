#!/usr/bin/env python3
"""link-search — fuzzy-search every link you've ever copied or browsed.

Unions two sources, then hands the ranked list to fuzzel (dmenu mode):
  1. Clipboard history  — every URL in cliphist's store (persistent capture runs
     via `wl-paste --watch cliphist store`, so this goes as far back as cliphist has).
  2. Browser history    — url + page title from Zen's places.sqlite (moz_places).

You can match on the page TITLE or the URL (like Zen's `^` history search).
Clipboard links are boosted: they sort first, and when a URL exists in both
sources the clipboard copy wins (and borrows the browser's title). On a result:
  Enter       → copy the markdown link  [title](url)
  Ctrl+Enter  → copy the bare URL

Bound to Super+Shift+V (see modules/home/hyprland/config.nix). Standalone:
just run `link-search`.
"""
from __future__ import annotations

import glob
import os
import re
import shutil
import subprocess
import sys
import tempfile

URL_RE = re.compile(r"https?://[^\s\"'<>`\]}]+")
# Trailing punctuation that clings to a copied URL but isn't part of it.
TRAILING_JUNK = ".,;:!?)]}>\"'"


def norm(url: str) -> str:
    """Normalize a URL for dedup: drop the #fragment, trailing slash, lowercase host."""
    u = url.split("#", 1)[0].rstrip("/")
    m = re.match(r"^(https?://)([^/]+)(.*)$", u, re.I)
    if not m:
        return u.lower()
    scheme, host, rest = m.groups()
    return f"{scheme.lower()}{host.lower()}{rest}"


def clean(url: str) -> str:
    return url.rstrip(TRAILING_JUNK)


# ---------------------------------------------------------------- clipboard --
def clipboard_links() -> list[str]:
    """Full URLs from cliphist history, newest first (list order preserved)."""
    try:
        listing = subprocess.run(
            ["cliphist", "list"], capture_output=True, text=True, timeout=15
        ).stdout.splitlines()
    except (FileNotFoundError, subprocess.SubprocessError):
        return []

    urls: list[str] = []
    seen: set[str] = set()
    for line in listing:
        if "http" not in line:
            continue
        # cliphist list truncates previews, so decode the entry for the full URL.
        try:
            full = subprocess.run(
                ["cliphist", "decode"],
                input=line,
                capture_output=True,
                text=True,
                timeout=5,
            ).stdout
        except subprocess.SubprocessError:
            full = line
        for m in URL_RE.findall(full):
            u = clean(m)
            k = norm(u)
            if k not in seen:
                seen.add(k)
                urls.append(u)
    return urls


# ------------------------------------------------------------------ browser --
def places_db() -> str | None:
    candidates = glob.glob(os.path.expanduser("~/.zen/*/places.sqlite")) + glob.glob(
        os.path.expanduser("~/.mozilla/firefox/*/places.sqlite")
    )
    candidates = [c for c in candidates if os.path.getsize(c) > 0]
    if not candidates:
        return None
    # Prefer the most recently written profile.
    return max(candidates, key=os.path.getmtime)


def browser_links() -> list[tuple[str, str]]:
    """(url, title) from browser history, ranked by frecency (visits, then recency)."""
    import sqlite3

    db = places_db()
    if not db:
        return []
    # places.sqlite is locked + WAL-backed while the browser runs — copy the db
    # plus its sidecar files to a temp dir and read that snapshot.
    tmp = tempfile.mkdtemp(prefix="link-search-")
    try:
        for suffix in ("", "-wal", "-shm"):
            src = db + suffix
            if os.path.exists(src):
                shutil.copy2(src, os.path.join(tmp, "places.sqlite" + suffix))
        con = sqlite3.connect(os.path.join(tmp, "places.sqlite"))
        rows = con.execute(
            """
            SELECT url, COALESCE(title, '')
            FROM moz_places
            WHERE url LIKE 'http%' AND COALESCE(hidden, 0) = 0
            ORDER BY visit_count DESC, last_visit_date DESC
            """
        ).fetchall()
        con.close()
        return [(clean(u), t) for u, t in rows]
    except Exception:
        return []
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


# -------------------------------------------------------------------- build --
def build_lines() -> tuple[list[str], dict[str, tuple[str, str]]]:
    clip = clipboard_links()
    browser = browser_links()
    title_by_url = {norm(u): t for u, t in browser if t}

    lines: list[str] = []
    entry_of: dict[str, tuple[str, str]] = {}  # display line -> (url, title)
    used: set[str] = set()

    def add(marker: str, url: str, title: str) -> None:
        k = norm(url)
        if k in used:
            return
        used.add(k)
        shown = url if len(url) <= 90 else url[:87] + "…"
        label = title.strip() or "(no title)"
        line = f"{marker}  {label}   —   {shown}"
        # fuzzel needs unique lines to map a selection back to its URL + title.
        while line in entry_of:
            line += " "
        lines.append(line)
        entry_of[line] = (url, title.strip())

    # Clipboard first (the boost): newest copies on top, titled from browser history.
    for url in clip:
        add("📋", url, title_by_url.get(norm(url), ""))
    # Then browser history, skipping anything already surfaced from the clipboard.
    for url, title in browser:
        add("🌐", url, title)

    return lines, entry_of


def fuzzel_config() -> str:
    """A temp fuzzel config = the user's theme + a Ctrl+Return binding (url-only).

    custom-1 makes fuzzel exit with code 10 while still printing the selection,
    which is how we distinguish the two copy actions. (Shift+Return / Ctrl+y are
    already bound by fuzzel to defaults, so Ctrl+Return is the free chord.)
    """
    base = os.path.expanduser("~/.config/fuzzel/fuzzel.ini")
    text = ""
    if os.path.exists(base):
        try:
            text = open(base, encoding="utf-8").read()
        except OSError:
            text = ""
    if "[key-bindings]" in text:
        text = text.replace("[key-bindings]", "[key-bindings]\ncustom-1=Control+Return", 1)
    else:
        text += "\n[key-bindings]\ncustom-1=Control+Return\n"
    fd, path = tempfile.mkstemp(prefix="link-search-fuzzel-", suffix=".ini")
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write(text)
    return path


def format_selection(url: str, title: str, url_only: bool) -> str:
    """Enter → markdown [title](url); Shift+Enter (url_only) → the bare URL."""
    if url_only:
        return url
    return f"[{title or url}]({url})"


def main() -> int:
    lines, entry_of = build_lines()
    if os.environ.get("LINK_SEARCH_DUMP"):  # print the fuzzel input and exit (debug)
        print("\n".join(lines))
        return 0
    if not lines:
        subprocess.run(
            ["notify-send", "link-search", "No links found in clipboard or browser history."]
        )
        return 0

    cfg = fuzzel_config()
    try:
        proc = subprocess.run(
            # Enter → copy markdown [title](url);  Shift+Enter → copy the URL only.
            ["fuzzel", "--dmenu", "--no-sort", "--config", cfg, "--width", "100",
             "--lines", "20", "--prompt", "link  ↵md  ^↵url  "],
            input="\n".join(lines),
            capture_output=True,
            text=True,
        )
    except FileNotFoundError:
        print("fuzzel not found", file=sys.stderr)
        return 1
    finally:
        os.unlink(cfg)

    picked = proc.stdout.strip()
    if not picked or proc.returncode not in (0, 10):  # 1/2/130 = dismissed
        return 0
    url, title = entry_of.get(picked, ("", ""))
    if not url:  # fuzzel returned custom text; fall back to any URL in the line.
        m = URL_RE.search(picked)
        url = clean(m.group(0)) if m else picked

    url_only = proc.returncode == 10  # Shift+Enter → custom-1
    out = format_selection(url, title, url_only)
    mode = "URL" if url_only else "markdown"
    subprocess.run(["wl-copy"], input=out, text=True)
    subprocess.run(["notify-send", "-t", "2000", "link-search", f"Copied {mode}: {out}"])
    return 0


if __name__ == "__main__":
    sys.exit(main())
