{pkgs, ...}: let
  captureScript = pkgs.writeScript "ntfy-capture-listener" ''
#!${pkgs.python3}/bin/python3
"""
ntfy capture listener.
Subscribes to the 'captures' ntfy topic and writes incoming messages
as markdown files to the Obsidian vault capture directory.
Runs as a long-lived systemd service.
"""

import json
import sys
import time
import urllib.request
from datetime import datetime
from pathlib import Path
import re

CAPTURE_DIR = Path("/home/matth/Obsidian/Main/capture/raw_capture/ntfy")

def sanitize_filename(text, max_len=50):
    clean = re.sub(r'[^\w\s-]', "", text[:max_len]).strip()
    clean = re.sub(r'\s+', '-', clean).lower()
    return clean or "capture"

def write_capture(msg):
    CAPTURE_DIR.mkdir(parents=True, exist_ok=True)

    timestamp = datetime.fromtimestamp(msg["time"])
    date_str = timestamp.strftime("%Y-%m-%d")
    time_str = timestamp.strftime("%H-%M-%S")

    title = msg.get("title", "")
    message = msg.get("message", "")
    tags = msg.get("tags", [])

    slug = sanitize_filename(title or message)
    filename = f"{date_str}_{time_str}_{slug}.md"
    filepath = CAPTURE_DIR / filename

    obsidian_tags = ["ntfy-capture"]
    if isinstance(tags, list):
        obsidian_tags.extend(tags)

    lines = [
        "---",
        f"tags: [{', '.join(obsidian_tags)}]",
        f"date: {date_str}",
        f"time: {timestamp.strftime('%H:%M:%S')}",
        "source: ntfy",
        "---",
        "",
    ]
    if title:
        lines.append(f"# {title}")
        lines.append("")

    lines.append(message)
    lines.append("")

    filepath.write_text("\n".join(lines))
    print(f"Captured: {filepath.name}")

def main():
    print("ntfy capture listener starting...")
    print(f"Watching topic: captures")
    print(f"Output dir: {CAPTURE_DIR}")

    while True:
        try:
            req = urllib.request.Request(
                "http://localhost:8124/captures/json",
                headers={"Accept": "application/x-ndjson"},
            )
            with urllib.request.urlopen(req) as resp:
                for line in resp:
                    line = line.decode("utf-8").strip()
                    if not line:
                        continue
                    try:
                        msg = json.loads(line)
                        if msg.get("event") == "message":
                            write_capture(msg)
                    except json.JSONDecodeError:
                        continue
        except Exception as e:
            print(f"Connection error: {e}, reconnecting in 10s...", file=sys.stderr)
            time.sleep(10)

if __name__ == "__main__":
    main()
  '';
in {
  systemd.services.ntfy-capture-listener = {
    description = "Listen for captures via ntfy and write to Obsidian vault";
    after = ["network.target" "ntfy-sh.service"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "simple";
      User = "matth";
      Restart = "always";
      RestartSec = 10;
      ExecStart = "${captureScript}";
    };
  };
}
