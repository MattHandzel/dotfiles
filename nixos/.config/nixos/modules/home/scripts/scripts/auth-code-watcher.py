#!/usr/bin/env python3
"""auth-code-watcher — put login/verification codes on the clipboard as they arrive.

Polls the Gmail inbox over IMAP (handzelmatthew@gmail.com, app password read at
runtime from ~/notes/.env: APP_PASSWORD), and in a second thread polls Beeper
Desktop's local API for texts (SMS via the Google Messages bridge, plus Signal,
WhatsApp, Telegram…; token read from ~/.config/beeper/access-token). When a
newly-arrived message looks like a 2FA / login / verification code, it extracts
the code, fires a desktop notification, and copies the code to the clipboard.

Secrets never touch the Nix store — the app password is read from ~/notes/.env at
runtime. Mail is fetched with BODY.PEEK so messages are NOT marked read.

Run modes:
  auth-code-watcher            # long-running poll loop (the launchd/systemd service)
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
import threading
import time
import urllib.parse
import urllib.request
from email.header import decode_header

EMAIL = "handzelmatthew@gmail.com"
ENV_FILE = os.path.expanduser("~/notes/.env")
IMAP_HOST = "imap.gmail.com"
POLL_SECONDS = 15
# Every socket op must be bounded. With no timeout, one half-open connection
# (sleep/wake, Wi-Fi change) parked the loop in SSL read forever: the agent
# stayed "running" under launchd, so nothing restarted it, and it went silent
# from 2026-10-04 17:13 until the 10-05 Swapcard code was missed.
IMAP_TIMEOUT = 30
BEEPER_API = "http://127.0.0.1:23373"
BEEPER_TOKEN_FILE = os.path.expanduser("~/.config/beeper/access-token")
BEEPER_POLL_SECONDS = 3  # local API, so poll fast: a texted code is wanted now
# Only codes younger than this are copied; older ones are expired, and copying
# them after an outage would just clobber the clipboard.
BEEPER_LOOKBACK = 600


def log(msg):
    """One timestamped line to stdout — launchd/systemd route it to the log file.
    The service used to be completely silent unless it crashed, which made
    "it didn't fire" indistinguishable from "it never saw the mail"."""
    print("%s %s" % (time.strftime("%Y-%m-%d %H:%M:%S"), msg), flush=True)


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


def copy_to_clipboard(code):
    """Put `code` on the system clipboard.

    IT MUST GO IN ON STDIN. `wl-copy` takes its text as an argument on Wayland,
    but on this Mac `wl-copy` is the compat shim in modules/home/darwin/
    compat-shims.nix, which is `pbcopy` — and pbcopy reads STDIN and ignores its
    argv. `wl-copy CODE` therefore copied nothing and left the clipboard EMPTY
    (measured 2026-09-20: clipboard went from a URL to 0 bytes). Piping works on
    both platforms, so stdin is the portable call.

    Returns True when the clipboard verifiably holds the code."""
    try:
        subprocess.run(["wl-copy"], input=code, text=True, check=False, timeout=10)
    except Exception as e:
        log("clipboard: wl-copy failed: %s" % e)
        return False
    # Read it back. Silent clipboard failures have bitten this machine before
    # (pbcopy's argv, and Wispr Flow's paste-and-restore race), so assert rather
    # than assume. Best effort: a missing wl-paste is not an error.
    try:
        got = subprocess.run(["wl-paste"], capture_output=True, text=True, timeout=10)
        if got.returncode == 0:
            if got.stdout.strip() == code:
                return True
            log("clipboard: readback mismatch (got %r, want %r)" % (got.stdout[:40], code))
            return False
    except Exception:
        pass
    return True


def notify(code, subject, sender):
    ok = copy_to_clipboard(code)
    tail = "(copied to clipboard)" if ok else "(COPY FAILED — clipboard not set)"
    subprocess.run(
        [
            "notify-send",
            "-u",
            "normal",
            "-i",
            "dialog-password",
            "Login code: %s" % code,
            "%s\n%s\n%s" % (sender, subject, tail),
        ],
        check=False,
    )
    log("code %s from %r (%s) copied=%s" % (code, sender[:60], subject[:60], ok))


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


def html_to_text(txt):
    # <style>/<script> CONTENTS must go before tags are stripped, or the mail
    # body becomes a wall of CSS. That buried the real code in Substack /
    # Amtrak / PayPal / Reddit mail and was a large source of junk candidates.
    txt = re.sub(r"(?is)<(style|script|head|title)\b[^>]*>.*?</\1\s*>", " ", txt)
    txt = re.sub(r"(?is)<!--.*?-->", " ", txt)
    txt = re.sub(r"(?i)<(br|/p|/div|/tr|/td|/h[1-6]|/li|/table)\b[^>]*>", "\n", txt)
    txt = re.sub(r"<[^>]+>", " ", txt)
    return html.unescape(txt)


def body_text(msg):
    plain, rich = [], []
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
        except Exception:
            continue
        # Keep BOTH parts: some senders (PayPal, Reddit) put the code only in
        # the HTML half, so preferring text/plain alone loses it.
        (plain if ct == "text/plain" else rich).append(
            txt if ct == "text/plain" else html_to_text(txt)
        )
    return "\n".join(plain + rich)


def normalize(txt):
    for ch in (" ", "​", "‌", "‍", "﻿"):
        txt = txt.replace(ch, " ")
    # URLs and addresses are dense with code-shaped junk (%2F -> "2Foverview").
    txt = re.sub(r"https?://\S+|www\.\S+", " ", txt)
    txt = re.sub(r"\b[\w.+-]+@[\w-]+\.[\w.]+\b", " ", txt)
    txt = re.sub(r"[ \t]+", " ", txt)
    # Collapse runs of blank lines: senders pad the code with dozens of empty
    # table rows, which pushes it far from its label in raw character distance.
    txt = re.sub(r"\n[ \t]*(?:\n[ \t]*)+", "\n", txt)
    return txt.strip()


# The message must SAY it carries a credential before we look for one. Gating on
# a bare "code" fired on promo codes, Linear issue keys and gate keypads.
STRONG = re.compile(
    r"(?:"
    r"verification\s+code|security\s+code|log[-\s]?in\s+code|sign[-\s]?in\s+code|"
    r"authentication\s+code|auth\s+code|access\s+code|temporary\s+code|single[-\s]?use\s+code|"
    r"one[-\s]?time\s+(?:code|password|passcode|pin)|passcode|\botp\b|"
    r"(?:2fa|two[-\s]?factor)[-\s]?(?:code|pin)?|confirmation\s+code|verification\s+pin|"
    r"security\s+pin|your\s+code\s+is|code\s+is\s*:?\s*\d|"
    r"code\s+to\s+(?:sign|log)\s*[-\s]?in|(?:enter|use|copy)\s+(?:this|the|following)\s+code|"
    r"code\s+below|following\s+(?:verification\s+)?code|your\s+code\s+for"
    r")",
    re.I,
)
# Looser — only used to locate the code once STRONG has admitted the message.
CTX = re.compile(r"\b(?:code|passcode|otp|pin|password)\b", re.I)
CTX_TIGHT = re.compile(
    r"\b(?:verification\s+code|security\s+code|login\s+code|passcode|\botp\b|"
    r"one[-\s]?time\s+(?:code|password|passcode)|code\s+is)\b",
    re.I,
)
# "code" that is not a credential.
NEG_WORD = re.compile(
    r"\b(?:discount|promo(?:tion(?:al)?)?|coupon|referral|invite|invitation|"
    r"gift|offer|voucher|qr|dress|area|zip|postal|country|error|status|"
    r"airport|fare|course|tracking|order|gate|door|entry|source)\s+code\b",
    re.I,
)
NEG_PROMO = re.compile(
    r"(?:\d{1,3}\s*%\s*off|% off|\boff your\b|\bat checkout\b|\bcoupon\b|"
    r"\bdiscount\b|\bpromo\b|\bsave big\b|\bfree shipping\b|\bdeal\b|"
    r"\border of\b|\bsubscribe\b|\bunsubscribe now\b)",
    re.I,
)
NEG_TRAVEL = re.compile(
    r"\b(?:flight|boarding|itinerary|reservation|booking|record\s+locator|"
    r"departure|airline|checked\s+bag|seat\s+assignment|hotel\s+stay)\b",
    re.I,
)
NEG_MEETING = re.compile(
    r"\b(?:meeting\s+id|teams\s+meeting|zoom\s+meeting|webinar|"
    r"conference\s+id|dial[-\s]?in|join\s+the\s+meeting|calendly|"
    r"google\s+meet|video\s+id|tenant\s+key)\b",
    re.I,
)
NEG_PLACE = re.compile(
    r"\b(?:keypad|automatic\s+gate|car\s+gate|walk[-\s]?in\s+gate|"
    r"lockbox|door\s+lock|front\s+door|buzzer|intercom|\bgate\b)",
    re.I,
)
NEG_EVENT = re.compile(
    r"\b(?:backup\s+codes?\s+(?:was|were)\s+used|generate\s+new\s+backup\s+codes|"
    r"one[-\s]?time\s+(?:transfer|payment|purchase|fee|offer|deal|only))\b",
    re.I,
)

DIGIT_HINT = re.compile(r"\b(\d{1,2})[-\s]?(?:digit|character|letter)\b", re.I)
HYPHEN = re.compile(r"\b([A-Z0-9]{3,4}(?:-[A-Z0-9]{3,4})+)\b")  # JIF-NYY, LZE-CBW
GOOGLE = re.compile(r"\bG-(\d{4,8})\b")  # G-123456, self-anchored
TOKEN = re.compile(r"\b([A-Za-z0-9]{4,10})\b")
IS_PREFIX = re.compile(r"(?:\bis|\bare|:|=)\s*$", re.I)
YEAR = re.compile(r"(?:19|20)\d{2}")
# Words shaped like codes but which are plain English or mail boilerplate.
STOP = {
    "code", "codes", "your", "this", "that", "with", "from", "here", "have", "will",
    "then", "only", "used", "using", "minutes", "minute", "expires", "expire",
    "please", "email", "login", "signin", "sign", "account", "enter", "below",
    "above", "team", "thanks", "valid", "next", "link", "click", "none", "auto",
    "left", "right", "center", "bold", "font", "size", "color", "body", "table",
    "true", "false", "null", "type", "name", "data", "text", "html", "head", "form",
    "input", "button", "verify", "verification", "security", "password", "passcode",
    "token", "about", "also", "been", "more", "than", "them", "they", "what", "when",
    "which", "would", "there", "into", "over", "just", "like", "make", "time", "user",
    "need", "help", "find", "open", "send", "copy", "paste", "field", "apply", "again",
    "request", "requested", "identity", "access", "expired", "within", "seconds", "hours",
}


def _line_bounds(blob, i):
    s = blob.rfind("\n", 0, i) + 1
    e = blob.find("\n", i)
    return s, (len(blob) if e == -1 else e)


def _kw_distance(blob, s, e, pattern, window=160):
    """Chars from [s,e) to the nearest match of `pattern`; None if none in range."""
    before, after = blob[max(0, s - window):s], blob[e:e + window]
    best = None
    for mm in pattern.finditer(before):
        d = len(before) - mm.end()
        best = d if best is None else min(best, d)
    for mm in pattern.finditer(after):
        d = mm.start()
        best = d if best is None else min(best, d)
    return best


def _rejected_locally(blob, s, e):
    w = blob[max(0, s - 140):e + 140]
    return bool(
        NEG_WORD.search(w) or NEG_PROMO.search(w) or NEG_TRAVEL.search(w)
        or NEG_MEETING.search(w) or NEG_PLACE.search(w)
    )


def _score(blob, tok, s, e, subj_len, hint):
    """How much this token looks like THE code. None = not a candidate."""
    if CTX.search(tok) or tok.lower() in STOP:
        return None
    up = any(c.isupper() for c in tok)
    lo = any(c.islower() for c in tok)
    dig = any(c.isdigit() for c in tok)
    if dig and not (up or lo):
        if not (4 <= len(tok) <= 8):            # 482910
            return None
    elif (up or lo) and dig:
        if not (4 <= len(tok) <= 10):           # 4t7B99, Wpv2CPUs, b5mcxdEKuw
            return None
    elif up and not lo and not dig:
        if not (5 <= len(tok) <= 8):            # FEPQVU
            return None
    else:
        return None                             # a pure lowercase word

    d = _kw_distance(blob, s, e, CTX)
    if d is None:
        return None
    sc = max(0.0, 60.0 - d * 0.5)               # closer to its label = better
    ls, le = _line_bounds(blob, s)
    if blob[ls:le].strip() == tok:
        sc += 100.0                             # alone on its line: the usual layout
    if IS_PREFIX.search(blob[max(0, s - 6):s]):
        sc += 45.0                              # "code is 693127" / "Code: 113340"
    if blob[e:le].strip() in ("", ".", "#", ".#"):
        sc += 20.0                              # ends the line
    if s < subj_len:
        sc += 45.0                              # subjects are short and on-topic
    if hint and len(tok) == hint:
        sc += 35.0                              # "the 6-digit code below"
    if (up or lo) and dig:
        sc += 15.0                              # mixed tokens are rarely prose
    if up and not lo and not dig:
        sc += 10.0
    if YEAR.fullmatch(tok):
        # "June 2026" is a date. Only a tight label right next to it makes it a code
        # (this is why "Your Vitalist Bay 2026 login code: 925027" used to yield 2026).
        if _kw_distance(blob, s, e, CTX_TIGHT, 60) is None:
            return None
        sc -= 70.0
    return sc


def find_code(subject, body, gate=STRONG):
    subject = normalize(subject or "")
    blob = normalize(subject + "\n" + (body or ""))
    subj_len = len(subject)
    if not gate.search(blob):
        return None
    if NEG_EVENT.search(blob) and not CTX_TIGHT.search(blob):
        return None
    hm = DIGIT_HINT.search(blob)
    hint = int(hm.group(1)) if hm and 3 <= int(hm.group(1)) <= 10 else None

    best = (None, 0.0)
    # 1) Hyphen-grouped device codes (LZE-CBW, GQ7-DGS): a distinctive shape.
    for m in HYPHEN.finditer(blob):
        tok = m.group(1)
        if CTX.search(tok) or not re.search(r"[A-Z]", tok):
            continue
        if _rejected_locally(blob, m.start(), m.end()):
            continue
        d = _kw_distance(blob, m.start(), m.end(), CTX)
        if d is None:
            continue
        sc = 120.0 + max(0.0, 60.0 - d * 0.5)
        ls, le = _line_bounds(blob, m.start())
        if blob[ls:le].strip() == tok:
            sc += 100.0
        if m.start() < subj_len:
            sc += 45.0
        if sc > best[1]:
            best = (tok, sc)
    # 2) Google's "G-123456" — the prefix anchors it, no context needed.
    m = GOOGLE.search(blob)
    if m:
        return m.group(1)
    # 3) Everything else, scored. Best candidate wins rather than the first one.
    for m in TOKEN.finditer(blob):
        if _rejected_locally(blob, m.start(), m.end()):
            continue
        sc = _score(blob, m.group(1), m.start(), m.end(), subj_len, hint)
        if sc is not None and sc > best[1]:
            best = (m.group(1), sc)
    return best[0] if best[1] >= 55.0 else None


# Texted codes are terser than mail and have no subject: "Code: 621543", "with
# the code 405902. Don't share it", "enter this 4 digit code …: 7708". STRONG
# alone caught 47 of 61 real code texts from Aug–Oct 2026, so texts also pass on
# a code mention next to the don't-share boilerplate nearly every one carries.
MSG_GATE = re.compile(
    STRONG.pattern
    + r"|\b(?:code|passcode|pin)\b[\s\S]{0,120}?(?:don'?t|do\s+not|never)\s+share"
    + r"|(?:don'?t|do\s+not|never)\s+share[\s\S]{0,120}?\b(?:code|passcode|pin)\b"
    + r"|\benter\s+(?:this|the|your)\s+(?:\d{1,2}[-\s]?digit\s+)?code\b"
    + r"|\bcode\s*:\s*[A-Za-z0-9]*\d",
    re.I,
)
MSG_MAX_CHARS = 320  # a code text is SMS-sized; longer is conversation


def find_message_code(text):
    """find_code for a chat/SMS message. The text is short and on-topic, so it
    stands in for a mail subject ("737461 is your Shop verification code")."""
    if "<" in text:
        text = html_to_text(text)  # Beeper hands over some networks' HTML
    if len(text) > MSG_MAX_CHARS:
        return None
    return find_code(text, "", gate=MSG_GATE)


def _beeper_search(token, params):
    url = BEEPER_API + "/v1/messages/search?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers={"Authorization": "Bearer " + token})
    with urllib.request.urlopen(req, timeout=10) as r:
        return json.load(r)


def watch_beeper():
    """Thread: copy codes from texts that land in Beeper Desktop. Every message
    from someone else in the last BEEPER_LOOKBACK seconds is checked once."""
    seen = set()
    primed = False
    down = None
    while True:
        try:
            with open(BEEPER_TOKEN_FILE) as f:
                token = f.read().strip()
            since = time.strftime(
                "%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() - BEEPER_LOOKBACK)
            )
            params = {
                "dateAfter": since,
                "sender": "others",
                "excludeLowPriority": "false",  # short-code senders land in Low Priority
                "includeMuted": "true",
                "limit": "20",  # the API's maximum
            }
            for _ in range(10):  # newest first; stop at the first page with nothing new
                page = _beeper_search(token, params)
                items = page.get("items", [])
                new = [m for m in items if (m.get("chatID"), m.get("id")) not in seen]
                for m in new:
                    seen.add((m.get("chatID"), m.get("id")))
                    if not primed:
                        continue
                    text = m.get("text") or ""
                    net = (m.get("accountID") or "?").split(".")[0]
                    who = m.get("senderName") or "?"
                    code = find_message_code(text)
                    if code:
                        notify(code, " ".join(text.split())[:80], "%s via %s" % (who, net))
                    else:
                        log("beeper: no code in %s message from %r" % (net, who[:40]))
                if not new or not page.get("hasMore") or not page.get("oldestCursor"):
                    break
                params.update(cursor=page["oldestCursor"], direction="before")
            if not primed:
                log("beeper: primed: %d recent message(s), watching for new texts" % len(seen))
                primed = True
            if down:
                log("beeper: reachable again")
                down = None
        except Exception as e:
            # Beeper not running, token missing/expired: say so once, keep trying.
            if str(e) != down:
                log("beeper: %s" % e)
                down = str(e)
        time.sleep(BEEPER_POLL_SECONDS)


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

    def __init__(self, host, ip, port=993, timeout=None):
        self._pinned_ip = ip
        super().__init__(host, port, timeout=timeout)

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
    if ip:
        M = _PinnedIMAP(IMAP_HOST, ip, timeout=IMAP_TIMEOUT)
    else:
        M = imaplib.IMAP4_SSL(IMAP_HOST, timeout=IMAP_TIMEOUT)
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
        elif notify_hits:
            log("no code in %r (%s)" % (sender[:50], subject[:60]))
    return found


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else ""
    pw = load_app_password()
    if not pw:
        msg = "APP_PASSWORD not found in %s" % ENV_FILE
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

    # Long-running poll loop (the service). Mark whatever is already UNSEEN as
    # seen on the first pass so we only notify for mail that arrives later.
    log("auth-code-watcher started (poll %ss, %s)" % (POLL_SECONDS, EMAIL))
    threading.Thread(target=watch_beeper, name="beeper", daemon=True).start()
    seen = set()
    first = True
    while True:
        try:
            M = connect(pw)
            scan(M, seen, notify_hits=not first)
            if first:
                log("primed: %d message(s) already unseen, watching for new mail" % len(seen))
            first = False
            M.logout()
        except Exception as e:
            log("IMAP error: %s" % e)
            subprocess.run(["notify-send", "auth-code-watcher", "IMAP error: %s" % e], check=False)
        time.sleep(POLL_SECONDS)


if __name__ == "__main__":
    main()
