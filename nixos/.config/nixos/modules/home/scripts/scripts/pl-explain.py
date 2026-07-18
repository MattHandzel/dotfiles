#!/usr/bin/env python3
"""pl-explain — quick Polish word/sentence lookup for a heritage speaker.

Reads clipboard (wl-paste), classifies as word vs sentence, asks `claude -p` for
a structured explanation, appends to projects/B2-polish/words-i-come-across-automatic.md,
and shows the result via notify-send.

Bound to numpad in Hyprland.
"""
import datetime
import os
import pathlib
import subprocess
import sys

VAULT = pathlib.Path.home() / "Obsidian" / "Main"
WORDS_FILE = VAULT / "projects" / "B2-polish" / "words-i-come-across-automatic.md"
CLAUDE_BIN = "/etc/profiles/per-user/matth/bin/claude"

WORD_PROMPT = """You are a Polish-language coach for a heritage speaker. His parents are Polish; Polish was his L1 until age 3-4. He's now relearning toward B2. Retained: ear, prosody, intuitive gender, basic aspect feel, accent. Missing: adult/abstract vocabulary, less-common case forms, idiomatic adult collocations, register awareness. Skip pronunciation/IPA — he has the ear.

He just copied this Polish word/short phrase while reading. Output a compact, scannable explanation in EXACTLY this format (4 lines, no extras):

**<lemma>** [POS · gender for nouns · aspect for verbs] — <short English gloss>
*<one-line Polish definition or close synonym>*
Kolokacje: *<collocation 1>*, *<collocation 2>*, *<collocation 3>*
Przykład: *<one natural B2-level Polish sentence using the headword>*

Output ONLY those four lines. No preamble, no commentary, no code fences.

Word/phrase: {input}
"""

SENTENCE_PROMPT = """You are a Polish-language coach for a heritage speaker. His parents are Polish; Polish was his L1 until age 3-4. He's now relearning toward B2. Retained: ear, intuition, basic aspect feel. Missing: adult vocabulary, formal case awareness, idiomatic adult collocations. Skip pronunciation/IPA.

He just copied this Polish phrase/sentence while reading. Output a compact explanation in EXACTLY this format (3 lines, no extras):

**Tłumaczenie:** <natural English translation>
**Gramatyka:** <only the non-obvious thing — case trigger, aspect choice, idiomatic structure; one sentence; output "—" if everything is transparent>
**Warto zapamiętać:** *<chunk 1>*, *<chunk 2>* — <one-line note on why these are worth keeping for adult Polish>

Output ONLY those three labeled lines. No preamble, no code fences.

Sentence: {input}
"""


def get_clipboard() -> str:
    return subprocess.run(
        ["wl-paste"], capture_output=True, text=True, check=True
    ).stdout.strip()


def call_claude(prompt: str, timeout: int = 90) -> str:
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
            "pl-explain",
            title,
            body,
        ],
        check=False,
    )


def initial_frontmatter() -> str:
    today = datetime.date.today().isoformat()
    return f"""---
id: words-i-come-across-automatic
aliases:
  - Words I Come Across (Automatic)
  - words-i-come-across-automatic
tags:
  - polish
  - ai-generated
created_date: "{today}"
last_edited_date: "{today}"
description: Auto-generated lookups via pl-explain (numpad KP_8). Each entry is a Polish word/phrase Matt copied while reading; Claude (heritage-speaker context) provided the explanation.
---

# Words I Come Across (Automatic)
"""


def main():
    try:
        text = get_clipboard()
    except subprocess.CalledProcessError as e:
        notify("pl-explain", f"clipboard read failed: {e}", "critical")
        sys.exit(1)

    if not text:
        notify("pl-explain", "clipboard is empty", "critical")
        sys.exit(1)

    token_count = len(text.split())
    is_word = token_count <= 4 and "." not in text and "!" not in text and "?" not in text
    template = WORD_PROMPT if is_word else SENTENCE_PROMPT
    prompt = template.format(input=text)

    notify("pl-explain", f"asking Claude: {text[:60]}…", "low")

    try:
        output = call_claude(prompt)
    except (subprocess.TimeoutExpired, RuntimeError) as e:
        notify("pl-explain failed", str(e)[:300], "critical")
        sys.exit(1)

    now = datetime.datetime.now()
    header = f"## {now.strftime('%Y-%m-%d %H:%M')} — {text[:80]}"
    block = f"\n{header}\n\n> {text}\n\n{output}\n"

    WORDS_FILE.parent.mkdir(parents=True, exist_ok=True)
    if not WORDS_FILE.exists():
        WORDS_FILE.write_text(initial_frontmatter())
    with WORDS_FILE.open("a") as f:
        f.write(block)

    notify("pl-explain", output)


if __name__ == "__main__":
    main()
