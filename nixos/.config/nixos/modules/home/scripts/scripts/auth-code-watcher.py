#!/usr/bin/env python3
"""auth-code-watcher — surface login/verification codes from email like Beeper does for texts.

Polls the Gmail inbox over IMAP (handzelmatthew@gmail.com, app password read at
runtime from ~/notes/.env: APP_PASSWORD). When a newly-arrived message looks like
a 2FA / login / verification code, it extracts the code, fires a desktop
notification, and copies the code to the Wayland clipboard.

Secrets never touch the Nix store — the app password is read from ~/notes/.env at
runtime. Mail is fetched with BODY.PEEK so messages are NOT marked read.

Run modes:
  auth-code-watcher            # long-running poll loop (the systemd service)
  auth-code-watcher --once     # single scan of UNSEEN, notify on any code found
  auth-code-watcher --selftest # print whether creds + IMAP login work, then exit
"""

import email
import html
import imaplib
import json
import os
import re
import socket
import subprocess
import sys
import time
import urllib.request
from email.header import decode_header

EMAIL = "handzelmatthew@gmail.com"
ENV_FILE = os.path.expanduser("~/notes/.env")
IMAP_HOST = "imap.gmail.com"
POLL_SECONDS = 15

# A real code sits RIGHT NEXT TO a code keyword ("your code is 482910"), not
# arbitrarily far from one. The old logic — "any context word anywhere + any
# 4-8 digit number anywhere" — false-positived on e.g. "June 2026" whenever the
# body happened to contain "confirm"/"sign in" somewhere. So we now require the
# candidate to be within a small same-line window of a keyword (proximity).

# Keywords that, when ADJACENT to a number, mark it as a code. Deliberately the
# STRONG set only — a real code is labelled by the word "code" (login/security/
# verification/access code), "passcode", "otp", "pin", "one-time", or "2fa". We do
# NOT use weak action phrases like "sign in" / "log in" / "confirm": those appear
# near order numbers, times, and years ("Sign in to track order #18452") and were
# the source of false positives.
KEYWORD = re.compile(
    r"\bcode\b|passcode|one[-\s]?time|\botp\b|\bpin\b|2fa|two[-\s]?factor|"
    r"verification|authentication code",
    re.I,
)
# Tighter set used to admit a bare 4-digit YEAR-looking number (e.g. 2026) only
# when it's unambiguously labelled a code rather than a date.
KEYWORD_TIGHT = re.compile(r"\bcode\b|passcode|\botp\b|\bpin\b|verification", re.I)

# Code token shapes.
CODE_ALNUM = re.compile(r"\b([A-Z0-9]{3,4}(?:-[A-Z0-9]{3,4})+)\b")  # JIF-NYY, GQ7-DGS (case-sensitive)
CODE_GOOGLE = re.compile(r"\bG-(\d{4,8})\b")  # G-123456 (self-anchored by the G- prefix)
CODE_DIGITS = re.compile(r"\b(\d{3}[-\s]?\d{3}|\d{4,8})\b")  # 464225, 123-456
_YEAR = re.compile(r"(?:19|20)\d{2}")


def load_app_password():
    try:
        with open(ENV_FILE) as f:
            for line in f:
                m = re.match(
                    r"""\s*(?:export\s+)?APP_PASSWORD=['"]?([^'"\n]+)['"]?\s*$""",
                    line,
                )
                if m:
                    return m.group(1).strip()
    except FileNotFoundError:
        pass
    return None


def notify(code, subject, sender):
    subprocess.run(
        [
            "notify-send",
            "-u",
            "normal",
            "-i",
            "dialog-password",
            f"Login code: {code}",
            f"{sender}\n{subject}\n(copied to clipboard)",
        ],
        check=False,
    )
    subprocess.run(["wl-copy", code], check=False)


def _decode(s):
    if not s:
        return ""
    out = ""
    for txt, enc in decode_header(s):
        if isinstance(txt, bytes):
            out += txt.decode(enc or "utf-8", "replace")
        else:
            out += txt
    return out


def body_text(msg):
    chunks = []
    parts = msg.walk() if msg.is_multipart() else [msg]
    for part in parts:
        ct = part.get_content_type()
        if ct not in ("text/plain", "text/html"):
            continue
        try:
            payload = part.get_payload(decode=True)
            if not payload:
                continue
            txt = payload.decode(part.get_content_charset() or "utf-8", "replace")
            if ct == "text/html":
                txt = html.unescape(re.sub(r"<[^>]+>", " ", txt))
            chunks.append(txt)
        except Exception:
            pass
    return "\n".join(chunks)


_PROXIMITY = 25  # chars between a keyword and the number for them to be "adjacent"


def _near_keyword(blob, start, end, pattern=KEYWORD):
    """True if a keyword sits within _PROXIMITY chars of [start,end) — searched in
    a window so the code and its label must actually be next to each other."""
    lo = max(0, start - _PROXIMITY)
    hi = min(len(blob), end + _PROXIMITY)
    return pattern.search(blob[lo:start]) is not None or pattern.search(blob[end:hi]) is not None


def find_code(subject, body):
    blob = f"{subject}\n{body}"

    # 1) Alphanumeric hyphen-grouped device codes (JIF-NYY, GQ7-DGS). The shape is
    #    distinctive, but still require it to contain a letter AND be near a keyword
    #    so things like "ABC-123" in prose don't trigger.
    for m in CODE_ALNUM.finditer(blob):
        tok = m.group(1)
        if re.search(r"[A-Z]", tok) and _near_keyword(blob, m.start(), m.end()):
            return tok

    # 2) Google-style "G-123456": the G- prefix is self-anchoring → no proximity
    #    needed.
    m = CODE_GOOGLE.search(blob)
    if m:
        return m.group(1)

    # 3) Plain digit codes — MUST be adjacent to a code keyword.
    for m in CODE_DIGITS.finditer(blob):
        raw = m.group(1)
        code = raw.replace(" ", "").replace("-", "")
        if not (4 <= len(code) <= 8):
            continue
        if not _near_keyword(blob, m.start(), m.end()):
            continue
        # A bare 4-digit year (1900-2099) is almost always a date, not a code
        # (e.g. "June 2026"). Only accept it if a TIGHT keyword (passcode/otp/pin/
        # code/verification — not "sign in"/"login") is right next to it.
        if len(code) == 4 and _YEAR.fullmatch(code) and not _near_keyword(blob, m.start(), m.end(), KEYWORD_TIGHT):
            continue
        return code

    return None


def _doh_resolve(name):
    """Resolve an A record via DNS-over-HTTPS to 1.1.1.1 (an IP literal, so a
    DNS-level blocklist like blocky cannot intercept it). Returns an IP or None."""
    url = "https://1.1.1.1/dns-query?name=%s&type=A" % name
    req = urllib.request.Request(url, headers={"accept": "application/dns-json"})
    with urllib.request.urlopen(req, timeout=10) as r:
        data = json.load(r)
    for ans in data.get("Answer", []):
        ip = ans.get("data", "")
        if ans.get("type") == 1 and ip and ip != "0.0.0.0":
            return ip
    return None


class _PinnedIMAP(imaplib.IMAP4_SSL):
    """IMAP4_SSL that dials a specific IP but keeps TLS SNI + cert validation for
    the real hostname — bypasses the system resolver while staying secure."""

    def __init__(self, host, ip, port=993):
        self._pinned_ip = ip
        super().__init__(host, port)

    def _create_socket(self, timeout=None):
        sock = socket.create_connection((self._pinned_ip, self.port), timeout)
        return self.ssl_context.wrap_socket(sock, server_hostname=self.host)


def connect(pw):
    # Resolve out-of-band via DoH so a focus DNS block on imap.gmail.com can't
    # take the watcher down — its whole job is to surface codes without email.
    ip = None
    try:
        ip = _doh_resolve(IMAP_HOST)
    except Exception:
        ip = None
    M = _PinnedIMAP(IMAP_HOST, ip) if ip else imaplib.IMAP4_SSL(IMAP_HOST)
    M.login(EMAIL, pw)
    M.select("INBOX")
    return M


def scan(M, seen, notify_hits):
    """Scan UNSEEN messages; notify for codes in UIDs not already in `seen`.

    Returns the list of codes found this pass (for --once / selftest reporting)."""
    found = []
    typ, data = M.uid("search", None, "(UNSEEN)")
    if typ != "OK" or not data or not data[0]:
        return found
    for uid in data[0].split():
        u = uid.decode()
        if u in seen:
            continue
        typ, msgdata = M.uid("fetch", uid, "(BODY.PEEK[])")
        seen.add(u)
        if typ != "OK":
            continue
        raw = next((p[1] for p in msgdata if isinstance(p, tuple)), None)
        if not raw:
            continue
        msg = email.message_from_bytes(raw)
        subject = _decode(msg.get("Subject"))
        sender = _decode(msg.get("From"))
        code = find_code(subject, body_text(msg))
        if code:
            found.append((code, subject, sender))
            if notify_hits:
                notify(code, subject, sender)
    return found


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else ""
    pw = load_app_password()
    if not pw:
        msg = f"APP_PASSWORD not found in {ENV_FILE}"
        if mode == "--selftest":
            print(msg)
        else:
            subprocess.run(["notify-send", "-u", "critical", "auth-code-watcher", msg], check=False)
        sys.exit(1)

    if mode == "--selftest":
        try:
            M = connect(pw)
            M.logout()
            print("OK: IMAP login to %s as %s succeeded." % (IMAP_HOST, EMAIL))
            sys.exit(0)
        except Exception as e:
            print("FAIL: %s" % e)
            sys.exit(1)

    if mode == "--once":
        M = connect(pw)
        hits = scan(M, set(), notify_hits=True)
        M.logout()
        print("\n".join("%s | %s" % (c, s) for c, s, _ in hits) or "no codes found")
        sys.exit(0)

    # Long-running poll loop (systemd service). Mark whatever is already UNSEEN
    # as seen on the first pass so we only notify for mail that arrives later.
    seen = set()
    first = True
    while True:
        try:
            M = connect(pw)
            scan(M, seen, notify_hits=not first)
            first = False
            M.logout()
        except Exception as e:
            subprocess.run(["notify-send", "auth-code-watcher", f"IMAP error: {e}"], check=False)
        time.sleep(POLL_SECONDS)


if __name__ == "__main__":
    main()
