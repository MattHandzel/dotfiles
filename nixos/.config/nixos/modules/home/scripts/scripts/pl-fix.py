#!/usr/bin/env python3
"""pl-fix — quick Polish fix while writing, for a heritage speaker.

Reads clipboard (Polish text Matt just wrote), asks `claude -p` for a corrected
version + 1-3 brief notes on what changed. Replaces clipboard with the corrected
text (paste-ready) and shows the explanations via notify-send. Logs every fix
to projects/B2-polish/fixes-log.md so Matt can see error patterns over time.

Bound to numpad in Hyprland.
"""
import datetime
import os
import pathlib
import re
import subprocess
import sys

VAULT = pathlib.Path.home() / "Obsidian" / "Main"
LOG_FILE = VAULT / "projects" / "B2-polish" / "fixes-log.md"
CLAUDE_BIN = "/etc/profiles/per-user/matth/bin/claude"

PROMPT = """You are a Polish-language coach for a heritage speaker. His parents are Polish; Polish was his L1 until age 3-4. He's now relearning toward B2. Retained: ear, prosody, intuition, gender feel, basic aspect feel, accent. Missing: adult vocabulary, formal case awareness, idiomatic adult collocations, register awareness.

He just wrote this Polish text and wants a quick fix he can paste back right now. The text MAY contain English words/phrases inside square brackets like `[reasons]` or `[i found out]` — these mark vocabulary gaps where he didn't know the Polish word. He may also offer a tentative Polish guess in parentheses after the bracket, e.g. `[reasons] (powody?)`.

Output EXACTLY this format — two sections separated by a line containing only `---`:

<corrected Polish text — bracketed English replaced with natural adult Polish (declined/conjugated to fit the sentence). All other errors silently fixed. Preserve his voice and meaning. Minimal-change unless an idiomatic rephrasing is clearly better.>

---

<one bullet per non-obvious change — bracket-fills + grammar/case/aspect fixes + idiomatic upgrades. Skip pure typos. Format each bullet as:

- **before → after** — *<grammatical category in Polish: przypadek / aspekt / rodzaj / liczba / rekcja / kolokacja / etc.>* — <plain-English explanation of WHY this change is required: which rule was violated, what triggers the new form (e.g., which preposition/verb governs which case, which gender forces which ending), and what the original form would mean if left as-is>. End with a one-line takeaway he can generalize ("Rule of thumb: …").

Be explicit about *which word triggers the change* — name the governing verb, preposition, or construction (e.g., "*nad* always takes narzędnik when expressing 'over/above' a topic you're working on"). For bracket-fills, also explain the chosen Polish word inline. If a guess in parentheses was correct, note "guess correct". If the input was already perfect, output exactly: "OK — already correct.">

Output ONLY those two sections separated by `---`. No preamble, no code fences, no extra commentary.

Text:
{input}
"""


def get_clipboard() -> str:
    return subprocess.run(
        ["wl-paste"], capture_output=True, text=True, check=True
    ).stdout.strip()


def set_clipboard(text: str):
    subprocess.run(["wl-copy"], input=text, text=True, check=True)


def call_claude(prompt: str, timeout: int = 60) -> str:
    env = os.environ.copy()
    result = subprocess.run(
        [CLAUDE_BIN, "--dangerously-skip-permissions", "--model", "sonnet", "-p", prompt],
        capture_output=True,
        text=True,
        timeout=timeout,
        cwd=str(VAULT),
        env=env,
    )
    if result.returncode != 0:
        raise RuntimeError(
            f"claude failed (rc={result.returncode}): {(result.stderr or result.stdout)[:500]}"
        )
    return result.stdout.strip()


def notify(title: str, body: str, urgency: str = "normal"):
    subprocess.run(
        [
            "notify-send",
            "-u",
            urgency,
            "-i",
            "dialog-information",
            "-a",
            "pl-fix",
            "-t",
            "15000",
            title,
            body,
        ],
        check=False,
    )


def initial_frontmatter() -> str:
    today = datetime.date.today().isoformat()
    return f"""---
id: fixes-log
aliases:
  - Polish Fixes Log
tags:
  - polish
  - ai-generated
created_date: "{today}"
last_edited_date: "{today}"
description: Auto-log of every pl-fix (numpad KP_9) invocation. Original → corrected → what changed. Scan for recurring categories to identify weak grammar areas.
---

# Polish Fixes Log
"""


def parse_output(output: str) -> tuple[str, str]:
    parts = re.split(r"^\s*---\s*$", output, maxsplit=1, flags=re.MULTILINE)
    if len(parts) == 2:
        return parts[0].strip(), parts[1].strip()
    return output.strip(), ""


def main():
    try:
        text = get_clipboard()
    except subprocess.CalledProcessError as e:
        print(f"pl-fix: clipboard read failed: {e}", file=sys.stderr)
        sys.exit(1)

    if not text:
        print("pl-fix: clipboard is empty", file=sys.stderr)
        sys.exit(1)

    print(f"━━━ pl-fix ━━━\n\nOriginal:\n  {text}\n\nFixing…\n", flush=True)

    try:
        output = call_claude(PROMPT.format(input=text))
    except (subprocess.TimeoutExpired, RuntimeError) as e:
        print(f"pl-fix failed: {e}", file=sys.stderr)
        sys.exit(1)

    corrected, notes = parse_output(output)

    set_clipboard(corrected)

    LOG_FILE.parent.mkdir(parents=True, exist_ok=True)
    if not LOG_FILE.exists():
        LOG_FILE.write_text(initial_frontmatter())
    now = datetime.datetime.now()
    entry = f"""
## {now.strftime('%Y-%m-%d %H:%M')}

**Original:**
> {text}

**Corrected:**
> {corrected}

**Notes:** {notes if notes else "—"}
"""
    with LOG_FILE.open("a") as f:
        f.write(entry)

    print(f"Corrected (in clipboard, paste-ready):\n  {corrected}\n")
    print(f"Zmiany:\n{notes if notes else '(brak / już OK)'}\n")


if __name__ == "__main__":
    main()
