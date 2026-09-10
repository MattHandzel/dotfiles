#!/usr/bin/env python3
"""Waybar meter for Wispr Flow: show the LIVE mic level while dictating and
colour the module by whether real audio is actually being captured.

Why this exists: the old `wispr-status` lit a red "REC" the instant Wispr held
any live PipeWire capture node — even a *silent* one (muted headset, wrong
default source). A dead-mic dictation looked identical to a good one, so a
5-minute brain dump could vanish while the bar showed a confident REC the whole
time. This module reads the actual audio and makes silence visible:

  off        Wispr not running              -> hidden
  idle       Wispr up, not dictating        -> dim mic
  listening  dictating AND hearing you      -> green, live level bar
  silent     dictating but mic ~silent      -> red alert (you're not heard)

It streams newline-delimited JSON to stdout; waybar reads one line per update.
Pure stdlib (Python 3.13 dropped audioop) — peak is computed from raw s16 PCM.
Our own capture does NOT steal the mic from Wispr; PipeWire tees the source to
every reader.
"""
import array
import collections
import json
import math
import subprocess
import sys
import time

WISPR_MATCH = "usr/lib/wispr-flow"  # every real Wispr child carries this path
RATE = 16000
CHANNELS = 1
CHUNK_MS = 100  # ~10 UI updates/sec while dictating
CHUNK_BYTES = int(RATE * CHANNELS * 2 * CHUNK_MS / 1000)
SILENCE_LEVEL = 0.02  # peak/full-scale below this (over the window) == not heard
WINDOW_CHUNKS = 12  # ~1.2s rolling max, de-flickers listening<->silent
CHECK_EVERY = 0.5  # how often to notice Wispr stopped so we release the mic

MIC = ""  # nf-fa-microphone
MIC_OFF = ""  # nf-fa-microphone_slash
BAR_CELLS = 6


def emit(text, cls, tooltip):
    sys.stdout.write(json.dumps({"text": text, "class": cls, "tooltip": tooltip}))
    sys.stdout.write("\n")
    sys.stdout.flush()


def wispr_pids():
    try:
        out = subprocess.run(
            ["pgrep", "-f", WISPR_MATCH], capture_output=True, text=True, timeout=2
        ).stdout
    except Exception:
        return set()
    return {p for p in out.split() if p}


def dictating(pids):
    """True iff Wispr owns a PipeWire capture node in the `running` state."""
    if not pids:
        return False
    try:
        dump = subprocess.run(
            ["pw-dump"], capture_output=True, text=True, timeout=3
        ).stdout
        nodes = json.loads(dump)
    except Exception:
        return False
    for obj in nodes:
        if obj.get("type") != "PipeWire:Interface:Node":
            continue
        info = obj.get("info") or {}
        if info.get("state") != "running":
            continue
        props = info.get("props") or {}
        if props.get("media.class") != "Stream/Input/Audio":
            continue
        if str(props.get("application.process.id")) in pids:
            return True
    return False


def bar(level):
    filled = int(round(level * BAR_CELLS))
    return "█" * filled + "▁" * (BAR_CELLS - filled)


def db_and_scaled(frac):
    if frac <= 0:
        return -99.0, 0.0
    db = 20.0 * math.log10(frac)
    scaled = max(0.0, min(1.0, (db + 50.0) / 50.0))  # -50..0 dBFS -> 0..1 bar
    return db, scaled


def peaks():
    """Own a capture stream on the default source and yield the peak (0..1) of
    each ~CHUNK_MS block. pw-record writes a WAV container to stdout, so strip
    the 44-byte RIFF header once if present."""
    proc = subprocess.Popen(
        [
            "pw-record",
            "--rate",
            str(RATE),
            "--channels",
            str(CHANNELS),
            "--format",
            "s16",
            "--latency",
            "80ms",
            "-",
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
    )
    try:
        head = proc.stdout.read(44)
        if head[:4] != b"RIFF":
            # Already raw PCM — feed the bytes we peeked back into the stream.
            carry = head
        else:
            carry = b""
        while True:
            need = CHUNK_BYTES - len(carry)
            chunk = carry + (proc.stdout.read(need) if need > 0 else b"")
            carry = b""
            if not chunk:
                break
            usable = len(chunk) - (len(chunk) % 2)
            samples = array.array("h")
            samples.frombytes(chunk[:usable])
            peak = 0
            for s in samples:
                a = -s if s < 0 else s
                if a > peak:
                    peak = a
            yield peak / 32768.0
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=1)
        except Exception:
            proc.kill()


def stream_while_dictating(pids):
    """Emit live level until Wispr's capture node disappears."""
    window = collections.deque(maxlen=WINDOW_CHUNKS)
    last_check = time.monotonic()
    for frac in peaks():
        window.append(frac)
        db, scaled = db_and_scaled(frac)
        if max(window) >= SILENCE_LEVEL:
            emit(f"{MIC} {bar(scaled)}", "listening", f"Wispr — listening ({db:.0f} dBFS)")
        else:
            emit(
                f"{MIC_OFF} {bar(0)}",
                "silent",
                "Wispr REC but the mic is SILENT — muted or wrong default source?",
            )
        now = time.monotonic()
        if now - last_check >= CHECK_EVERY:
            last_check = now
            if not dictating(pids):
                return


def main():
    state = None
    while True:
        pids = wispr_pids()
        if not pids:
            if state != "off":
                emit("", "off", "Wispr Flow not running")
                state = "off"
            time.sleep(1.5)
            continue
        if not dictating(pids):
            if state != "idle":
                emit(MIC, "idle", "Wispr Flow ready (not dictating)")
                state = "idle"
            time.sleep(0.7)
            continue
        state = "recording"
        stream_while_dictating(pids)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
