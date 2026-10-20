#!/usr/bin/env python3
"""wispr-learn: teach Wispr Flow the corrections you make in Neovim (or anywhere).

Wispr Flow's own "learn from edits" only sees edits made inside the macOS
Accessibility snapshot it takes of the target text field for a short window
after it pastes. In kitty/Neovim that snapshot is unreliable (History rows for
kitty end with contentObservationEndReason = textbox_emptied) and anything
edited later, or after a paste from the clipboard, is never seen. That is why
"UVM" -> "Neovim" was never learned (2026-09-17 Oops).

This does what Wispr's learner does internally, from outside:

  scan     text on stdin -> find the recent dictations (flow.sqlite History)
           that appear in it, word-align dictated vs current text, and add each
           bounded substitution as a Dictionary row with source=user_edits and
           observedSource=<what Wispr heard>. Those are exactly the rows Wispr's
           own learner writes, so they show up as auto-learned entries in the
           app and are pushed to the server on Wispr's next dictionary sync
           (app start, opening the Dictionary page, or any dictionary edit).
           Every candidate is first checked by Claude (`claude -p`): only an
           edit that fixes a misrecognition is learned, not a change of mind
           like "10" -> "25" (2026-10-06 Oops).
  add      add one phrase by hand (--heard "what Wispr wrote", --replacement)
  recent   list the most recently added entries

State: ~/.local/state/wispr-learn/{learn.log,seen.json}.
"""

from __future__ import annotations

import argparse
import difflib
import json
import os
import re
import shutil
import sqlite3
import subprocess
import sys
import time
import urllib.request
import uuid
from datetime import datetime, timedelta, timezone

# WISPR_LEARN_DB points a test at a scratch copy instead of the live database.
DB = os.environ.get("WISPR_LEARN_DB") or os.path.expanduser(
    "~/Library/Application Support/Wispr Flow/flow.sqlite"
)
PERSONAL_TEAM = "00000000-0000-0000-0000-000000000000"
STATE_DIR = os.path.expanduser("~/.local/state/wispr-learn")
CACHE_DIR = os.path.expanduser("~/.cache/wispr-learn")
# The same list Wispr's DictionaryManager.loadStopwords fetches (15k words, many
# languages): a candidate made only of these is never learned.
STOPWORDS_URL = (
    "https://wispr-flow-cdn.s3.us-west-2.amazonaws.com/static/data/"
    "dictionary_stopwords.json"
)
FALLBACK_STOPWORDS = set(
    """a about above after again against all am an and any are as at be because
    been before being below between both but by can could did do does doing down
    during each few for from further had has have having he her here hers him his
    how i if in into is it its just like me more most my no nor not now of off on
    once only or other our out over own same she should so some such than that
    the their them then there these they this those through to too under until up
    very was we were what when where which while who whom why will with would you
    your yes okay ok thing things something get got make made want really going
    go know think said say one two also well much many""".split()
)
WORD_RE = re.compile(r"[^\W_]+(?:['’][^\W_]+)*")
MAX_PHRASE_WORDS = 4  # Wispr's cap for a learned phrase
MAX_PER_DICTATION = 4  # Wispr's classifier cap per edited dictation
MIN_DICTATION_WORDS = 4
MIN_MATCH_RATIO = 0.6  # share of the dictation's words found in the text
MIN_SOUND_ALIKE = 0.5  # difflib ratio heard~corrected for all-lowercase words
ENGLISH_WORDS = "/usr/share/dict/words"  # macOS ships it; a lowercase real word is likely a rewording
# The heuristics above only pre-filter. Each surviving candidate goes to Claude,
# which tells a misrecognition ("Arian" -> "Aryan") from a change of mind
# ("10" -> "25"), the judgement Wispr's server classifier makes for its own learner.
JUDGE_MODEL = "sonnet"
JUDGE_TIMEOUT = 90
JUDGE_SYSTEM = """You review candidate entries for a speech-recognition personal \
dictionary (Wispr Flow). Each candidate comes from one dictation: `dictated` is what \
the recognizer typed, `edited` is the same passage after the user edited it by hand, \
and the edit replaced `heard` with `corrected`.

Answer learn=true only when the replacement fixes a RECOGNITION ERROR: the user said \
`corrected` and the recognizer wrote something that sounds like it, typically a \
misheard or misspelled name, proper noun, brand, acronym or jargon term.

Answer learn=false when the user changed what they meant instead: a different number \
or amount, a reworded or replaced phrase, added or removed detail, a word with a \
different meaning, a fix to their own wording, or a half-typed word. When `heard` and \
`corrected` do not sound alike it is almost always an edit, not a recognition error. \
When unsure, answer learn=false: a wrong entry makes later dictation worse.

Give a short reason for each verdict."""
JUDGE_SCHEMA = {
    "type": "object",
    "properties": {
        "verdicts": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "id": {"type": "integer"},
                    "learn": {"type": "boolean"},
                    "reason": {"type": "string"},
                },
                "required": ["id", "learn", "reason"],
            },
        }
    },
    "required": ["verdicts"],
}


class JudgeError(Exception):
    pass


def claude_cli() -> str | None:
    path = os.path.expanduser("~/.local/bin/claude")
    return path if os.access(path, os.X_OK) else shutil.which("claude")


def judge(cands: list[dict[str, str]]) -> dict[int, tuple[bool, str]]:
    """Ask Claude which candidates are misrecognitions: {index: (learn, reason)}.

    --safe-mode keeps the OAuth login but skips hooks, CLAUDE.md, plugins and MCP
    servers, so the call is a bare model request (about 3 s). Raises JudgeError
    when Claude cannot answer; the caller then learns nothing.
    """
    claude = claude_cli()
    if not claude:
        raise JudgeError("claude CLI not found")
    payload = [{"id": i, **c} for i, c in enumerate(cands)]
    os.makedirs(STATE_DIR, exist_ok=True)
    try:
        res = subprocess.run(
            [
                claude, "-p", "--safe-mode", "--model", JUDGE_MODEL,
                "--tools", "", "--strict-mcp-config", "--no-session-persistence",
                "--output-format", "json", "--json-schema", json.dumps(JUDGE_SCHEMA),
                "--system-prompt", JUDGE_SYSTEM,
            ],
            input=json.dumps(payload, ensure_ascii=False),
            capture_output=True,
            text=True,
            timeout=JUDGE_TIMEOUT,
            cwd=STATE_DIR,
        )
    except (OSError, subprocess.TimeoutExpired) as e:
        raise JudgeError(str(e)) from e
    try:
        out = json.loads(res.stdout)
    except ValueError:
        raise JudgeError(f"exit {res.returncode}: {(res.stderr or res.stdout).strip()[:200]}")
    if res.returncode != 0 or out.get("is_error") or not isinstance(out.get("structured_output"), dict):
        raise JudgeError(f"exit {res.returncode}: {str(out.get('result'))[:200]}")
    verdicts: dict[int, tuple[bool, str]] = {}
    for v in out["structured_output"].get("verdicts", []):
        if isinstance(v.get("id"), int) and 0 <= v["id"] < len(cands):
            verdicts[v["id"]] = (v.get("learn") is True, str(v.get("reason", "")))
    return verdicts


def english_words() -> set[str]:
    try:
        with open(ENGLISH_WORDS, encoding="utf-8", errors="ignore") as f:
            return {w.strip().lower() for w in f if w.strip()}
    except OSError:
        return set()


def now_utc() -> datetime:
    return datetime.now(timezone.utc)


def wispr_ts(dt: datetime) -> str:
    """Sequelize's sqlite DATETIME text: 2026-09-16 23:28:37.884 +00:00."""
    return dt.strftime("%Y-%m-%d %H:%M:%S.") + f"{dt.microsecond // 1000:03d}" + " +00:00"


def log(line: str) -> None:
    os.makedirs(STATE_DIR, exist_ok=True)
    with open(os.path.join(STATE_DIR, "learn.log"), "a", encoding="utf-8") as f:
        f.write(f"{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}  {line}\n")


def load_seen() -> set[str]:
    try:
        with open(os.path.join(STATE_DIR, "seen.json"), encoding="utf-8") as f:
            return set(json.load(f))
    except (OSError, ValueError):
        return set()


def save_seen(seen: set[str]) -> None:
    os.makedirs(STATE_DIR, exist_ok=True)
    with open(os.path.join(STATE_DIR, "seen.json"), "w", encoding="utf-8") as f:
        json.dump(sorted(seen)[-5000:], f)


def stopwords() -> set[str]:
    path = os.path.join(CACHE_DIR, "dictionary_stopwords.json")
    try:
        if time.time() - os.path.getmtime(path) > 7 * 86400:
            raise OSError("stale")
        with open(path, encoding="utf-8") as f:
            return {w.lower() for w in json.load(f)}
    except (OSError, ValueError):
        pass
    try:
        with urllib.request.urlopen(STOPWORDS_URL, timeout=5) as r:
            data = json.load(r)
        os.makedirs(CACHE_DIR, exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            json.dump(data, f)
        return {w.lower() for w in data}
    except Exception:  # offline: fall back to a small English list
        return set(FALLBACK_STOPWORDS)


def connect(readonly: bool = False) -> sqlite3.Connection:
    if not os.path.exists(DB):
        sys.exit(f"wispr-learn: no Wispr Flow database at {DB}")
    uri = f"file:{DB}?mode={'ro' if readonly else 'rw'}"
    con = sqlite3.connect(uri, uri=True, timeout=5)
    con.row_factory = sqlite3.Row
    return con


def dictionary_phrases(con: sqlite3.Connection) -> set[str]:
    rows = con.execute(
        "select phrase from Dictionary where isDeleted = 0 and teamDictionaryId = ?",
        (PERSONAL_TEAM,),
    )
    return {r["phrase"].strip().lower() for r in rows}


def insert_phrase(
    con: sqlite3.Connection,
    phrase: str,
    observed: str | None,
    source: str,
    manual: bool,
    replacement: str | None,
) -> str:
    """Insert (or undelete) one personal dictionary row. Returns its id.

    Mirrors DictionaryManager.addAutoLearnedWords / addManualWord: user_edits
    rows carry frequencyUsed=1 and the misheard form in observedSource; manual
    rows carry manualEntry=1 and source=manual. remoteFrequencyUsed stays 0 so
    Wispr's next syncDictionary() pushes the row to the server (it uploads any
    local row the server does not know and then updates remoteFrequencyUsed).
    """
    ts = wispr_ts(now_utc())
    new_id = str(uuid.uuid4())
    with con:  # short IMMEDIATE transaction; Wispr's own writes wait on the WAL lock
        con.execute("begin immediate")
        con.execute(
            """
            insert into Dictionary
              (id, phrase, replacement, teamDictionaryId, lastUsed, frequencyUsed,
               remoteFrequencyUsed, manualEntry, createdAt, modifiedAt, isDeleted,
               source, isSnippet, observedSource, isStarred, replacementHtml)
            values (?, ?, ?, ?, ?, ?, 0, ?, ?, ?, 0, ?, 0, ?, 0, null)
            on conflict(phrase, teamDictionaryId) do update set
              isDeleted = 0,
              modifiedAt = excluded.modifiedAt,
              lastUsed = excluded.lastUsed,
              observedSource = coalesce(excluded.observedSource, Dictionary.observedSource),
              replacement = coalesce(excluded.replacement, Dictionary.replacement),
              source = excluded.source,
              manualEntry = excluded.manualEntry,
              frequencyUsed = Dictionary.frequencyUsed + excluded.frequencyUsed
            where Dictionary.isDeleted = 1
            """,
            (
                new_id,
                phrase,
                replacement,
                PERSONAL_TEAM,
                ts,
                0 if manual else 1,
                1 if manual else 0,
                ts,
                ts,
                source,
                observed,
            ),
        )
    row = con.execute(
        "select id from Dictionary where phrase = ? and teamDictionaryId = ?",
        (phrase, PERSONAL_TEAM),
    ).fetchone()
    return row["id"] if row else new_id


def tokens(text: str) -> list[str]:
    return WORD_RE.findall(text)


def candidates_for(
    dictated: list[str], buffer: list[str]
) -> tuple[list[tuple[str, str]], tuple[int, int]] | None:
    """Word-align one dictation against the text. None = dictation not present.

    Returns (corrected phrase, what Wispr heard) pairs for every substitution
    that is bounded by matching words on both sides, the same shape Wispr's
    learner extracts from its `[CMZ]S[CMZ]` word-label regex, plus the
    [start, end) word span of the text the dictation aligned to.
    """
    d_norm = [w.lower() for w in dictated]
    b_norm = [w.lower() for w in buffer]
    sm = difflib.SequenceMatcher(None, d_norm, b_norm, autojunk=False)
    blocks = [b for b in sm.get_matching_blocks() if b.size > 0]
    if not blocks:
        return None
    matched = sum(b.size for b in blocks)
    if matched / len(dictated) < MIN_MATCH_RATIO:
        return None
    span = blocks[-1].b + blocks[-1].size - blocks[0].b
    if span > 2 * len(dictated) + 10:  # matches scattered over the file, not one paste
        return None
    ops = sm.get_opcodes()
    out: list[tuple[str, str]] = []
    for k, (tag, i1, i2, j1, j2) in enumerate(ops):
        if tag != "replace":
            continue
        before_ok = k == 0 or ops[k - 1][0] == "equal"
        after_ok = k == len(ops) - 1 or ops[k + 1][0] == "equal"
        if not (before_ok and after_ok):
            continue
        heard, corrected = dictated[i1:i2], buffer[j1:j2]
        if not (1 <= len(heard) <= MAX_PHRASE_WORDS and 1 <= len(corrected) <= MAX_PHRASE_WORDS):
            continue
        out.append((" ".join(corrected), " ".join(heard)))
    return out, (blocks[0].b, blocks[-1].b + blocks[-1].size)


def looks_like_transcription_fix(phrase: str, heard: str, english: set[str]) -> bool:
    """Cheap pre-filter in front of judge(), Wispr's classifier stand-in.

    Proper nouns / jargon (a capital or a digit: Neovim, Chrome, MATS, 6W2) are
    always plausible. An all-lowercase phrase is kept when it contains a word
    that is not plain English (neovim, tmux, espanso: the recogniser only ever
    writes real words, so the fix is the jargon) or when it sounds like what
    was heard (kitty <- kiddie). A rewording of one real word into another
    (nice -> clean, get -> prefer) is not turned into a dictionary entry.
    """
    if any(c.isupper() or c.isdigit() for c in phrase):
        return True
    if english and any(w.lower() not in english for w in phrase.split()):
        return True
    return difflib.SequenceMatcher(None, phrase.lower(), heard.lower()).ratio() >= MIN_SOUND_ALIKE


def cmd_scan(args: argparse.Namespace) -> int:
    text = sys.stdin.read()
    spans = [m.span() for m in WORD_RE.finditer(text)]
    buffer = [text[a:b] for a, b in spans]
    if len(buffer) < MIN_DICTATION_WORDS:
        print("[]" if args.json else "wispr-learn: text too short")
        return 0
    con = connect(readonly=args.dry_run)
    cutoff = wispr_ts(now_utc() - timedelta(hours=args.since))
    rows = con.execute(
        """
        select transcriptEntityId as id, timestamp,
               coalesce(nullif(pastedText, ''), nullif(formattedText, ''), asrText) as text
        from History
        where timestamp > ? and isArchived = 0 and coalesce(numWords, 0) >= ?
        order by timestamp desc limit ?
        """,
        (cutoff, MIN_DICTATION_WORDS, args.limit),
    ).fetchall()
    if not rows:
        print("[]" if args.json else f"wispr-learn: no dictations in the last {args.since:g} h")
        return 0
    known = dictionary_phrases(con)
    stop = stopwords()
    english = english_words()
    seen = load_seen()
    learned: list[dict[str, str]] = []
    pending: list[tuple[sqlite3.Row, str, str, str]] = []  # row, phrase, heard, edited passage
    for row in rows:
        if not row["text"]:
            continue
        dictated = tokens(row["text"])
        if len(dictated) < MIN_DICTATION_WORDS:
            continue
        aligned = candidates_for(dictated, buffer)
        if not aligned or not aligned[0]:
            continue
        cands, (j1, j2) = aligned
        edited = text[spans[j1][0] : spans[j2 - 1][1]]
        picked: list[tuple[str, str]] = []
        for phrase, heard in cands:
            key = f"{row['id']}\t{phrase.lower()}"
            if phrase.lower() == heard.lower():
                continue
            if all(w.lower() in stop for w in phrase.split()):
                continue
            if phrase.lower() in known or key in seen:
                continue
            if not looks_like_transcription_fix(phrase, heard, english):
                continue
            if any(p.lower() == phrase.lower() for p, _ in picked):
                continue
            picked.append((phrase, heard))
        # Wispr sends capitalised candidates first and keeps at most 4.
        picked.sort(key=lambda ph: not any(c.isupper() for c in ph[0]))
        for phrase, heard in picked[:MAX_PER_DICTATION]:
            pending.append((row, phrase, heard, edited))
    verdicts: dict[int, tuple[bool, str]] = {}
    if pending:
        try:
            verdicts = judge(
                [
                    {"dictated": row["text"].strip(), "edited": edited, "heard": heard, "corrected": phrase}
                    for row, phrase, heard, edited in pending
                ]
            )
        except JudgeError as e:
            # Unchecked candidates are not marked seen, so the next :w retries them.
            log(f"judge failed, learned nothing from {len(pending)} candidate(s): {e}")
            con.close()
            print(f"wispr-learn: Claude could not check the candidates ({e}); nothing learned", file=sys.stderr)
            return 2
    dry = "DRY-RUN " if args.dry_run else ""
    for i, (row, phrase, heard, _) in enumerate(pending):
        key = f"{row['id']}\t{phrase.lower()}"
        if i not in verdicts:
            log(f"judge gave no verdict for {phrase!r} (heard {heard!r}); retried on the next scan")
            continue
        ok, reason = verdicts[i]
        origin = f"from dictation {row['id'][:8]} @ {row['timestamp']}: {reason}"
        if not ok:
            if not args.dry_run:
                seen.add(key)
            log(f"{dry}rejected {phrase!r} (heard {heard!r}) {origin}")
            continue
        if phrase.lower() in known:  # learned from an earlier dictation in this scan
            continue
        entry = {"phrase": phrase, "observedSource": heard, "transcriptEntityId": row["id"], "reason": reason}
        if not args.dry_run:
            entry["id"] = insert_phrase(con, phrase, heard, "user_edits", False, None)
            known.add(phrase.lower())
            seen.add(key)
        learned.append(entry)
        log(f"{dry}learned {phrase!r} (heard {heard!r}) {origin}")
    if not args.dry_run:
        save_seen(seen)
    con.close()
    if args.json:
        print(json.dumps(learned, ensure_ascii=False))
    elif learned:
        for e in learned:
            print(f"{'would learn' if args.dry_run else 'learned'}: {e['phrase']}  (heard: {e['observedSource']})")
    else:
        print("wispr-learn: nothing new to learn")
    return 0


def cmd_add(args: argparse.Namespace) -> int:
    phrase = " ".join(args.phrase).strip()
    if not phrase:
        sys.exit("wispr-learn add: empty phrase")
    con = connect()
    if phrase.lower() in dictionary_phrases(con):
        print(f"already in the dictionary: {phrase}")
        return 0
    source = "user_edits" if args.heard and not args.replacement else "manual"
    row_id = insert_phrase(
        con, phrase, args.heard, source, source == "manual", args.replacement
    )
    con.close()
    log(f"added {phrase!r} heard={args.heard!r} replacement={args.replacement!r} id={row_id}")
    print(f"added: {phrase}" + (f"  (heard: {args.heard})" if args.heard else ""))
    return 0


def cmd_recent(args: argparse.Namespace) -> int:
    con = connect(readonly=True)
    rows = con.execute(
        """
        select phrase, replacement, source, observedSource, frequencyUsed,
               remoteFrequencyUsed, modifiedAt, isDeleted
        from Dictionary where teamDictionaryId = ?
        order by modifiedAt desc limit ?
        """,
        (PERSONAL_TEAM, args.n),
    ).fetchall()
    for r in rows:
        heard = f"  heard: {r['observedSource']}" if r["observedSource"] else ""
        rep = f"  -> {r['replacement']}" if r["replacement"] else ""
        synced = "synced" if r["remoteFrequencyUsed"] else "not yet synced"
        deleted = "  [deleted]" if r["isDeleted"] else ""
        print(f"{r['modifiedAt'][:19]}  {r['source']:<10} {r['phrase']}{rep}{heard}  ({synced}){deleted}")
    return 0


def main() -> int:
    p = argparse.ArgumentParser(prog="wispr-learn", description=__doc__.split("\n\n")[0])
    sub = p.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("scan", help="learn corrections from the text on stdin")
    s.add_argument("--since", type=float, default=6, help="hours of dictations to consider (default 6)")
    s.add_argument("--limit", type=int, default=40, help="max dictations to align (default 40)")
    s.add_argument("--dry-run", action="store_true", help="report, do not write")
    s.add_argument("--json", action="store_true", help="print a JSON list of learned entries")
    s.set_defaults(fn=cmd_scan)
    a = sub.add_parser("add", help="add one phrase by hand")
    a.add_argument("phrase", nargs="+")
    a.add_argument("--heard", help="what Wispr wrote instead (stored as observedSource)")
    a.add_argument("--replacement", help="expand the phrase to this text when dictated")
    a.set_defaults(fn=cmd_add)
    r = sub.add_parser("recent", help="list the newest dictionary entries")
    r.add_argument("n", nargs="?", type=int, default=10)
    r.set_defaults(fn=cmd_recent)
    args = p.parse_args()
    return args.fn(args)


if __name__ == "__main__":
    sys.exit(main())
