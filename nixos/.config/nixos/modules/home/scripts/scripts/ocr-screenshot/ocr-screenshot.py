#!/usr/bin/env python3
"""ocr-screenshot — select a screen region, OCR it, copy the text to the clipboard.

Linux (Hyprland): grimblast picks the region (mouse drag) and copies the image.
macOS:            `screencapture -i` picks the region (drag, or space for a window).
Both then run the tesseract CLI directly — no pytesseract/Pillow needed — and put
the cleaned text on the clipboard (wl-copy / pbcopy). Stdlib only.
"""
import os
import platform
import subprocess
import sys
import tempfile

DARWIN = platform.system() == "Darwin"


def take_screenshot(file_path: str) -> None:
    """Capture a user-selected region into file_path (exit 1 if cancelled)."""
    if DARWIN:
        # -i interactive, -o no window shadow, -x no camera sound.
        cmd = ["/usr/sbin/screencapture", "-i", "-o", "-x", file_path]
    else:
        cmd = ["grimblast", "--notify", "copysave", "area", file_path]
    try:
        subprocess.run(cmd, check=True)
    except subprocess.CalledProcessError:
        print("Screenshot capture canceled or failed")
        sys.exit(1)
    except FileNotFoundError:
        print(f"{cmd[0]} not found.")
        sys.exit(1)
    if not os.path.exists(file_path) or os.path.getsize(file_path) == 0:
        # screencapture exits 0 on Escape but writes nothing.
        print("Screenshot capture canceled")
        sys.exit(1)


def copy_text(text: str) -> None:
    cmd = ["pbcopy"] if DARWIN else ["wl-copy"]
    subprocess.run(cmd, input=text.encode("utf-8"), check=False)


def ocr_from_screenshot() -> None:
    fd, screenshot_path = tempfile.mkstemp(suffix=".png")
    os.close(fd)
    print("Select area to capture (click and drag)...")
    try:
        take_screenshot(screenshot_path)
        try:
            out = subprocess.run(
                ["tesseract", screenshot_path, "stdout"],
                capture_output=True,
                check=True,
            ).stdout.decode("utf-8", "replace")
        except FileNotFoundError:
            print("Tesseract OCR not found (nix: pkgs.tesseract; brew: tesseract).")
            sys.exit(1)
        except subprocess.CalledProcessError as exc:
            print("Error: tesseract failed:", exc.stderr.decode("utf-8", "replace"))
            sys.exit(1)
        cleaned_text = "\n".join(line for line in out.split("\n") if line.strip())
        print("\nExtracted Text:\n")
        print(cleaned_text)
        copy_text(cleaned_text)
    finally:
        try:
            os.unlink(screenshot_path)
        except OSError:
            pass


if __name__ == "__main__":
    ocr_from_screenshot()
