#!/usr/bin/env python3
"""pl-correct — deep Polish journal correction using the master coach prompt.

Reads clipboard (a Polish journal entry, with `[english]` brackets for vocab gaps),
loads resources/prompts/my-written-polish-to-higher-quality-exercise.md, sends it
together with the text to `claude -p`, saves the 4-output result to
projects/B2-polish/corrections/<timestamp>.md, and opens it in a floating
kitty+nvim window.

Bound to numpad in Hyprland.
"""
import datetime
import os
import pathlib
import re
import subprocess
import sys

VAULT = pathlib.Path.home() / "Obsidian" / "Main"
PROMPT_FILE = VAULT / "resources" / "prompts" / "my-written-polish-to-higher-quality-exercise.md"
OUTPUT_DIR = VAULT / "projects" / "B2-polish" / "corrections"
CLAUDE_BIN = "/etc/profiles/per-user/matth/bin/claude"


def get_clipboard() -> str:
    return subprocess.run(
        ["wl-paste"], capture_output=True, text=True, check=True
    ).stdout.strip()


def load_prompt() -> str:
    raw = PROMPT_FILE.read_text()
    body = re.sub(r"^---.*?---\s*", "", raw, count=1, flags=re.DOTALL)
    body = re.split(r"^### Input Data", body, maxsplit=1, flags=re.MULTILINE)[0]
    return body.strip()


def call_claude(prompt: str, timeout: int = 300) -> str:
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
            "pl-correct",
            title,
            body,
        ],
        check=False,
    )


def main():
    try:
        text = get_clipboard()
    except subprocess.CalledProcessError as e:
        notify("pl-correct", f"clipboard read failed: {e}", "critical")
        sys.exit(1)

    if not text or len(text) < 20:
        notify(
            "pl-correct",
            "clipboard too short — copy a Polish journal entry first",
            "critical",
        )
        sys.exit(1)

    system = load_prompt()
    full_prompt = f"{system}\n\n### Input Data\n\n```\n{text}\n```\n"

    notify("pl-correct", "running deep correction (~30-90s)…", "low")

    try:
        output = call_claude(full_prompt)
    except (subprocess.TimeoutExpired, RuntimeError) as e:
        notify("pl-correct failed", str(e)[:300], "critical")
        sys.exit(1)

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    now = datetime.datetime.now()
    out_file = OUTPUT_DIR / f"{now.strftime('%Y-%m-%d-%H%M')}.md"
    iso = now.isoformat(timespec="minutes")

    body = f"""---
id: correction-{now.strftime('%Y-%m-%d-%H%M')}
created_date: "{now.date().isoformat()}"
tags:
  - polish
  - correction
  - ai-generated
---

# Polish Correction — {iso}

## Original (input)

```
{text}
```

---

{output}
"""
    out_file.write_text(body)

    notify("pl-correct", f"saved → {out_file.name}, opening…")
    subprocess.Popen(
        [
            "kitty",
            "--class",
            "floating-pl",
            "--title",
            "Polish Correction",
            "-e",
            "nvim",
            str(out_file),
        ],
        start_new_session=True,
    )


if __name__ == "__main__":
    main()
