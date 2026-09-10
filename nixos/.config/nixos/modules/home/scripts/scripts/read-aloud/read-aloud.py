#!/usr/bin/env python3
"""read-aloud — hit a key, hear the thing you're looking at.

Desktop-wide, not a browser extension: the text is resolved from whatever you
were actually doing, in this order.

  1. Primary selection — text highlighted in ANY app. Wayland's primary selection
     needs no copy keystroke, so highlighting *is* the gesture.
  2. Clipboard — a URL is fetched and stripped to prose; plain text is read as-is.
  3. Focused browser tab — there is no way to ask the browser directly without an
     extension, so the focused window's title is matched against Zen/Firefox
     history (places.sqlite) to recover the URL. Same trick as link-search.

Long articles start playing before they finish synthesizing: the text is chunked
on sentence boundaries and each chunk is appended to a running mpv playlist as it
arrives, so time-to-first-word stays a second or two regardless of length.

Playback is one mpv instance on an IPC socket, so `read-aloud --toggle` from a
second keybind pauses/resumes it, and `--stop` kills it.
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import re
import shutil
import socket
import sqlite3
import subprocess
import sys
import tempfile
import threading
import urllib.request

RUNTIME = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
IPC_SOCK = os.path.join(RUNTIME, "read-aloud.sock")
STATE_DIR = os.path.join(RUNTIME, "read-aloud")

# Kokoro (natural prosody, GPU) is the voice we want; the Piper service is kept as
# a fallback so a server that has not rebuilt yet — or a Kokoro container that is
# down — degrades to a worse voice instead of silence.
KOKORO_URL = os.environ.get("READ_ALOUD_TTS_URL", "http://100.118.206.104:8880").rstrip("/")
PIPER_URL = os.environ.get("READ_ALOUD_TTS_FALLBACK_URL", "http://100.118.206.104:47773").rstrip("/")
KOKORO_VOICE = os.environ.get("READ_ALOUD_VOICE", "af_heart")
PIPER_VOICE = os.environ.get("READ_ALOUD_FALLBACK_VOICE", "en_US-lessac-high")
SPEED = os.environ.get("READ_ALOUD_SPEED", "1.0")

# Small enough that the first chunk synthesizes fast (that is the latency actually
# felt), large enough that sentences keep their prosody.
CHUNK_CHARS = 600

USER_AGENT = "Mozilla/5.0 (X11; Linux x86_64) read-aloud"


def notify(title: str, body: str = "", urgency: str = "normal") -> None:
    subprocess.run(
        ["notify-send", "-u", urgency, "-a", "read-aloud", title, body], check=False
    )


# ---------------------------------------------------------------------------
# Controlling an already-running player
# ---------------------------------------------------------------------------
def mpv_command(command: list):
    if not os.path.exists(IPC_SOCK):
        return None
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
            s.settimeout(2)
            s.connect(IPC_SOCK)
            s.sendall((json.dumps({"command": command}) + "\n").encode())
            return json.loads(s.recv(65536).decode().splitlines()[0])
    except (OSError, ValueError, IndexError):
        return None


def player_alive() -> bool:
    return mpv_command(["get_property", "pid"]) is not None


def stop_playback() -> None:
    mpv_command(["quit"])
    shutil.rmtree(STATE_DIR, ignore_errors=True)


# ---------------------------------------------------------------------------
# Resolving what to read
# ---------------------------------------------------------------------------
def wl_paste(primary: bool = False) -> str:
    cmd = ["wl-paste", "-n"] + (["-p"] if primary else [])
    try:
        out = subprocess.run(cmd, capture_output=True, timeout=5)
        return out.stdout.decode("utf-8", "replace").strip()
    except (OSError, subprocess.SubprocessError):
        return ""


def focused_window() -> tuple[str, str]:
    try:
        out = subprocess.run(
            ["hyprctl", "activewindow", "-j"], capture_output=True, timeout=5
        )
        win = json.loads(out.stdout or "{}")
        return win.get("class", ""), win.get("title", "")
    except (OSError, ValueError, subprocess.SubprocessError):
        return "", ""


def url_from_browser_history(title: str) -> str:
    """Recover the focused tab's URL by matching its window title against history.

    Browsers put the page title (not the URL) in the window title, and there is no
    extension-free way to query the active tab. The tab you are looking at is
    necessarily in history, so match on title, newest visit first.
    """
    # Zen/Firefox suffix the window title with the browser name.
    page = re.sub(r"\s+[-—]\s+(Zen Browser|Mozilla Firefox|Firefox)\s*$", "", title).strip()
    if not page:
        return ""

    dbs = glob.glob(os.path.expanduser("~/.zen/*/places.sqlite")) + glob.glob(
        os.path.expanduser("~/.mozilla/firefox/*/places.sqlite")
    )
    for db in dbs:
        # The live DB is locked by the running browser; read a copy.
        with tempfile.NamedTemporaryFile(suffix=".sqlite") as tmp:
            try:
                shutil.copyfile(db, tmp.name)
                con = sqlite3.connect(f"file:{tmp.name}?immutable=1", uri=True)
                row = con.execute(
                    "SELECT url FROM moz_places WHERE title = ? "
                    "ORDER BY last_visit_date DESC LIMIT 1",
                    (page,),
                ).fetchone()
                con.close()
                if row and row[0].startswith("http"):
                    return row[0]
            except (OSError, sqlite3.Error):
                continue
    return ""


def looks_like_url(text: str) -> bool:
    return bool(re.fullmatch(r"https?://\S+", text.strip()))


def extract_article(url: str) -> tuple[str, str]:
    """(title, prose) for a URL, with nav/ads/boilerplate stripped."""
    import trafilatura

    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=30) as resp:
        html = resp.read().decode("utf-8", "replace")

    text = trafilatura.extract(html, include_comments=False, include_tables=False) or ""
    meta = trafilatura.extract_metadata(html)
    title = (getattr(meta, "title", "") or url) if meta else url
    return title, text.strip()


BROWSER_CLASSES = ("zen", "firefox", "navigator", "chrom", "brave", "vivaldi", "librewolf")


def is_browser(cls: str) -> bool:
    cls = (cls or "").lower()
    return any(b in cls for b in BROWSER_CLASSES)


def resolve_text(source: str) -> tuple[str, str]:
    """(title, text) to read, per the precedence in the module docstring."""
    if source in ("auto", "selection"):
        sel = wl_paste(primary=True)
        if len(sel) > 20:
            if looks_like_url(sel):
                return extract_article(sel)
            return "Selection", sel
        if source == "selection":
            return "", ""

    # In auto mode, if you are looking at a browser, the tab you're on is almost
    # always what you mean — so read it BEFORE falling back to the clipboard.
    # (The old order let a stale, unrelated clipboard silently win over the tab,
    # which is exactly the "it's not reading what's on my browser" bug.)
    if source == "auto":
        cls, title = focused_window()
        if is_browser(cls):
            url = url_from_browser_history(title)
            if url:
                return extract_article(url)

    if source in ("auto", "clipboard"):
        clip = wl_paste()
        if looks_like_url(clip):
            return extract_article(clip)
        if len(clip) > 20:
            return "Clipboard", clip
        if source == "clipboard":
            return "", ""

    if source in ("auto", "tab"):
        cls, title = focused_window()
        url = url_from_browser_history(title)
        if url:
            return extract_article(url)

    return "", ""


# ---------------------------------------------------------------------------
# Synthesis + playback
# ---------------------------------------------------------------------------
def chunk_text(text: str) -> list[str]:
    """Split on sentence boundaries into ~CHUNK_CHARS pieces."""
    text = re.sub(r"\s*\n\s*", " ", text).strip()
    sentences = re.split(r"(?<=[.!?])\s+", text)

    chunks, cur = [], ""
    for sentence in sentences:
        if cur and len(cur) + len(sentence) + 1 > CHUNK_CHARS:
            chunks.append(cur)
            cur = sentence
        else:
            cur = f"{cur} {sentence}".strip()
    if cur:
        chunks.append(cur)
    return chunks


def _post_audio(endpoint: str, payload: dict, timeout: int = 180) -> bytes:
    req = urllib.request.Request(
        endpoint,
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.read()


def synthesize(text: str, path: str) -> bool:
    """One chunk -> one audio file, Kokoro first, Piper if Kokoro is unreachable.

    Kokoro speaks the OpenAI /v1/audio/speech dialect; the home server's Piper
    service has its own /speak. Both are spoken here so the backend can change
    server-side without touching the client.
    """
    backends = [
        (
            f"{KOKORO_URL}/v1/audio/speech",
            {
                "model": "kokoro",
                "input": text,
                "voice": KOKORO_VOICE,
                "response_format": "mp3",
                "speed": float(SPEED),
            },
        ),
        (
            f"{PIPER_URL}/speak",
            {
                "text": text,
                "format": "mp3",
                "speed": float(SPEED),
                "voice": PIPER_VOICE,
            },
        ),
    ]

    last_error = ""
    for endpoint, payload in backends:
        try:
            audio = _post_audio(endpoint, payload)
        except OSError as exc:
            last_error = f"{endpoint}: {exc}"
            continue
        with open(path, "wb") as fh:
            fh.write(audio)
        return True

    notify("read-aloud: TTS failed", last_error, "critical")
    return False


def play(title: str, chunks: list[str], tee_path: str | None = None) -> None:
    """Stream the text through mpv. With `tee_path`, also save the synthesized
    audio to that file — reusing the very chunks being played, so tee costs no
    extra TTS calls. Tee runs the synthesis synchronously (keeping the process
    alive so the file actually gets written); mpv plays on after we exit."""
    os.makedirs(STATE_DIR, exist_ok=True)

    first = os.path.join(STATE_DIR, "000.mp3")
    if not synthesize(chunks[0], first):
        return
    parts = [first]

    subprocess.Popen(
        [
            "mpv",
            "--no-video",
            "--no-terminal",
            f"--input-ipc-server={IPC_SOCK}",
            "--idle=yes",
            "--keep-open=no",
            first,
        ],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )

    words = sum(len(c.split()) for c in chunks)
    notify(f"▶ {title[:60]}", f"{words} words · ~{max(1, words // 150)} min")

    # Remaining chunks synthesize while the first is already playing, and are
    # appended to mpv's playlist as they land — this is what keeps startup fast on
    # a long article.
    def rest() -> None:
        for i, chunk in enumerate(chunks[1:], start=1):
            os.makedirs(STATE_DIR, exist_ok=True)  # survive a --stop mid-tee
            path = os.path.join(STATE_DIR, f"{i:03d}.mp3")
            if not synthesize(chunk, path):
                return
            parts.append(path)
            # Tee keeps synthesizing the whole file even if playback was stopped;
            # play-only stops burning TTS cycles the moment mpv is gone.
            if mpv_command(["loadfile", path, "append"]) is None and not tee_path:
                return

    if tee_path:
        rest()
        saved = _stitch(parts, tee_path)
        if saved:
            _saved_note(title, chunks, saved)
    else:
        threading.Thread(target=rest, daemon=True).start()


def set_speed(speed: float) -> None:
    mpv_command(["set_property", "speed", speed])


def toggle_pause():
    if not player_alive():
        return None
    mpv_command(["cycle", "pause"])
    p = mpv_command(["get_property", "pause"])
    return bool(p and p.get("data"))


def _stitch(parts: list[str], out_path: str) -> str | None:
    """Concatenate the chunk mp3s into `out_path`; return the resolved path (or
    None on failure). Same codec (.mp3) -> stream-copy; any other extension
    (.wav/.opus/…) -> ffmpeg re-encodes to that container by name."""
    out_path = os.path.abspath(os.path.expanduser(out_path))
    if not os.path.splitext(out_path)[1]:
        out_path += ".mp3"  # a bare name has no format for ffmpeg to infer
    ext = os.path.splitext(out_path)[1].lower()
    os.makedirs(os.path.dirname(out_path) or ".", exist_ok=True)

    if len(parts) == 1 and ext == ".mp3":
        shutil.copyfile(parts[0], out_path)
        return out_path

    with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False) as lf:
        lf.writelines(f"file '{p}'\n" for p in parts)
        listing = lf.name
    try:
        copy = ["-c", "copy"] if ext == ".mp3" else []
        done = subprocess.run(
            ["ffmpeg", "-y", "-f", "concat", "-safe", "0", "-i", listing, *copy, out_path],
            capture_output=True,
        )
    finally:
        os.unlink(listing)
    if done.returncode != 0:
        notify("read-aloud: file write failed", done.stderr.decode("utf-8", "replace")[-300:], "critical")
        return None
    return out_path


def _saved_note(title: str, chunks: list[str], path: str) -> None:
    words = sum(len(c.split()) for c in chunks)
    notify(f" Saved · {title[:50]}", f"{words} words → {path}")
    print(path)


def write_to_file(title: str, chunks: list[str], out_path: str) -> int:
    """Synthesize the whole text and save it as one audio file, no playback."""
    tmp = tempfile.mkdtemp(prefix="read-aloud-out-")
    try:
        parts = []
        for i, chunk in enumerate(chunks):
            part = os.path.join(tmp, f"{i:03d}.mp3")
            if not synthesize(chunk, part):
                return 1
            parts.append(part)
        saved = _stitch(parts, out_path)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    if not saved:
        return 1
    _saved_note(title, chunks, saved)
    return 0


def _resolve(source: str, text: str) -> tuple[str, str]:
    """(title, body) for `source` (or literal `text`); ("", "") on failure,
    having already notified why."""
    if text:
        return "Text", text
    notify("read-aloud: fetching…")
    try:
        title, body = resolve_text(source)
    except Exception as exc:  # noqa: BLE001 — surface any extraction failure
        notify("read-aloud: could not get text", str(exc), "critical")
        return "", ""
    if not body:
        notify(
            "read-aloud: nothing to read",
            "Highlight text, copy a URL, or focus a browser tab.",
            "critical",
        )
        return "", ""
    return title, body


def start_read(source: str, text: str = "") -> int:
    """Stop whatever's playing and start reading `source` (or literal `text`)."""
    if player_alive():
        stop_playback()
    title, body = _resolve(source, text)
    if not body:
        return 1
    play(title, chunk_text(body))
    return 0


def save_read(source: str, text: str, out_path: str, tee: bool = False) -> int:
    """Synthesize `source` (or literal `text`) to a file. With `tee`, also play
    it aloud while saving; otherwise save silently."""
    title, body = _resolve(source, text)
    if not body:
        return 1
    chunks = chunk_text(body)
    if tee:
        if player_alive():
            stop_playback()
        play(title, chunks, tee_path=out_path)
        return 0
    return write_to_file(title, chunks, out_path)


def run_menu() -> int:
    """A fuzzel control panel — the transport controls without memorized keys.

    Playback controls only appear when something is playing; the three source
    options are always present so a press with nothing playing starts a read.
    """
    entries: list[tuple[str, tuple]] = []
    if player_alive():
        p = mpv_command(["get_property", "pause"])
        paused = bool(p and p.get("data"))
        sp = mpv_command(["get_property", "speed"])
        speed = (sp or {}).get("data", 1.0) if sp else 1.0
        mark = lambda s: "   ●" if abs(speed - s) < 0.01 else ""
        entries += [
            ("▶  Resume" if paused else "⏸  Pause", ("toggle",)),
            ("⏪  Rewind 15s", ("seek", -15)),
            ("⏩  Forward 15s", ("seek", 15)),
            (f"🐢  Speed 0.75×{mark(0.75)}", ("speed", 0.75)),
            (f"🔊  Speed 1.0×{mark(1.0)}", ("speed", 1.0)),
            (f"🐇  Speed 1.25×{mark(1.25)}", ("speed", 1.25)),
            (f"🐇  Speed 1.5×{mark(1.5)}", ("speed", 1.5)),
            ("⏹  Stop", ("stop",)),
        ]
    entries += [
        ("🖍  Read selection", ("read", "selection")),
        ("🌐  Read this tab", ("read", "tab")),
        ("📋  Read clipboard", ("read", "clipboard")),
    ]

    labels = "\n".join(label for label, _ in entries)
    try:
        proc = subprocess.run(
            ["fuzzel", "--dmenu", "--prompt", "read-aloud  "],
            input=labels.encode(),
            capture_output=True,
            timeout=120,
        )
    except (OSError, subprocess.SubprocessError):
        notify("read-aloud: menu failed", "fuzzel not available", "critical")
        return 1

    action = dict(entries).get(proc.stdout.decode().strip())
    if not action:
        return 0
    kind = action[0]
    if kind == "toggle":
        toggle_pause()
    elif kind == "stop":
        stop_playback()
    elif kind == "seek":
        mpv_command(["seek", action[1], "relative"])
    elif kind == "speed":
        set_speed(action[1])
    elif kind == "read":
        return start_read(action[1])
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(prog="read-aloud")
    ap.add_argument(
        "--source",
        choices=["auto", "selection", "clipboard", "tab"],
        default="auto",
        help="where to take the text from (default: auto — selection, clipboard, then browser tab)",
    )
    ap.add_argument("--toggle", action="store_true", help="pause/resume playback")
    ap.add_argument("--stop", action="store_true", help="stop playback")
    ap.add_argument("--seek", type=int, metavar="SECONDS", help="seek relative, e.g. -15")
    ap.add_argument("--menu", action="store_true", help="fuzzel control panel (transport + source)")
    ap.add_argument(
        "--output",
        "-o",
        metavar="PATH",
        help="synthesize to an audio file instead of playing (format from the extension: .mp3/.wav/.opus; bare name defaults to .mp3)",
    )
    ap.add_argument(
        "--tee",
        action="store_true",
        help="with --output, also play the audio aloud while saving it",
    )
    ap.add_argument("text", nargs="*", help="read this text instead of resolving a source")
    args = ap.parse_args()

    if args.tee and not args.output:
        ap.error("--tee requires --output")

    if args.menu:
        return run_menu()

    if args.output:
        return save_read(args.source, " ".join(args.text), args.output, tee=args.tee)

    if args.stop:
        stop_playback()
        return 0

    if args.toggle:
        if not player_alive():
            notify("read-aloud: nothing playing")
            return 1
        mpv_command(["cycle", "pause"])
        paused = mpv_command(["get_property", "pause"])
        notify("⏸ Paused" if paused and paused.get("data") else "▶ Resumed")
        return 0

    if args.seek is not None:
        mpv_command(["seek", args.seek, "relative"])
        return 0

    # A second press while something is playing means "read this instead"
    # (start_read stops any current playback first).
    return start_read(args.source, " ".join(args.text))


if __name__ == "__main__":
    sys.exit(main())
