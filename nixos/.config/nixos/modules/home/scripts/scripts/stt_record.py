#!/home/matth/.venvs/stt/bin/python
# -*- coding: utf-8 -*-

import argparse
import collections
import contextlib
import io
import json
import os
import signal
import subprocess
import sys
import tempfile
import time
from typing import Deque, List, Tuple, Optional

try:
    import webrtcvad
except Exception:
    webrtcvad = None


# ----------------------- Helpers -----------------------


def ffmpeg_input_cmd(backend: str, device: str) -> List[str]:
    """Return ffmpeg input args for the given backend/device."""
    if backend == "alsa":
        return ["-f", "alsa", "-i", device]
    else:
        return ["-f", "pulse", "-i", device]


def extract_text_from_json(raw_bytes: bytes) -> str:
    """Extract text from Whisper-like JSON output."""
    try:
        s = raw_bytes.decode("utf-8", errors="replace")
        data = json.loads(s)
    except Exception:
        return raw_bytes.decode("utf-8", errors="replace")

    if isinstance(data, dict):
        if isinstance(data.get("text"), str):
            return data["text"]
        if isinstance(data.get("transcript"), str):
            return data["transcript"]
        if isinstance(data.get("segments"), list):
            return "".join(seg.get("text", "") for seg in data["segments"])
    return json.dumps(data)


def write_wav(frames: List[bytes], sample_rate: int) -> bytes:
    import wave

    buf = io.BytesIO()
    with wave.open(buf, "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(sample_rate)
        for fr in frames:
            wf.writeframes(fr)
    return buf.getvalue()


def upload_file_curl(
    server_url: str,
    wav_path: str,
    language: Optional[str],
    extra_fields: List[Tuple[str, str]],
) -> Optional[bytes]:
    """
    Use curl to upload audio and return raw bytes.
    Swallows curl's stderr to avoid polluting stdout; returns None on failure.
    """
    url = f"{server_url.rstrip('/')}/v1/audio/transcriptions"
    cmd = ["curl", "-sS", url, "-F", f"file=@{wav_path}"]
    if language:
        cmd += ["-F", f"language={language}"]
    for k, v in extra_fields:
        cmd += ["-F", f"{k}={v}"]
    try:
        return subprocess.check_output(cmd, stderr=subprocess.DEVNULL)
    except subprocess.CalledProcessError:
        # Silent fail (log minimal message to stderr); don't impact stdout piping.
        sys.stderr.write("[stt] server upload failed (ignored)\n")
        sys.stderr.flush()
        return None


def longest_overlap_suffix_prefix(a: str, b: str) -> int:
    """Longest suffix of 'a' that is a prefix of 'b'."""
    max_len = min(len(a), len(b))
    for L in range(max_len, 0, -1):
        if a.endswith(b[:L]):
            return L
    return 0


# ----------------------- VAD Segmenter -----------------------


class VADSegmenter:
    """WebRTC VAD-based utterance segmenter."""

    def __init__(
        self,
        sample_rate=16000,
        frame_ms=30,
        vad_level=2,
        silence_ms=600,
        pre_roll_ms=200,
        max_utterance_ms=30000,
    ):
        if webrtcvad is None:
            raise RuntimeError("webrtcvad not installed (python3Packages.webrtcvad).")

        assert frame_ms in (10, 20, 30)
        self.rate = sample_rate
        self.frame_ms = frame_ms
        self.vad = webrtcvad.Vad(vad_level)
        self.silence_frames_needed = max(1, int(round(silence_ms / frame_ms)))
        self.pre_frames_max = max(0, int(round(pre_roll_ms / frame_ms)))
        self.max_frames = max(1, int(round(max_utterance_ms / frame_ms)))
        self.frame_bytes = int(self.rate * (self.frame_ms / 1000.0) * 2)

        self.reset()

    def reset(self):
        self.triggered = False
        self.silence_run = 0
        self.cur_frames: List[bytes] = []
        self.pre_frames: Deque[bytes] = collections.deque(maxlen=self.pre_frames_max)
        self.frames_in_utt = 0

    def push(self, chunk: bytes) -> List[List[bytes]]:
        completed: List[List[bytes]] = []
        for i in range(0, len(chunk), self.frame_bytes):
            fr = chunk[i : i + self.frame_bytes]
            if len(fr) < self.frame_bytes:
                break
            is_speech = self.vad.is_speech(fr, self.rate)
            if not self.triggered:
                self.pre_frames.append(fr)
                if is_speech:
                    self.triggered = True
                    self.cur_frames = list(self.pre_frames)
                    self.silence_run = 0
                    self.frames_in_utt = len(self.cur_frames)
            else:
                self.cur_frames.append(fr)
                self.frames_in_utt += 1
                if is_speech:
                    self.silence_run = 0
                else:
                    self.silence_run += 1
                if (
                    self.silence_run >= self.silence_frames_needed
                    or self.frames_in_utt >= self.max_frames
                ):
                    completed.append(self.cur_frames)
                    self.reset()
        return completed

    def flush(self) -> Optional[List[bytes]]:
        if self.triggered and self.cur_frames:
            out = self.cur_frames
            self.reset()
            return out
        return None


# ----------------------- Main -----------------------


def main():
    ap = argparse.ArgumentParser(
        description="Stream or batch transcribe audio to stdout."
    )
    ap.add_argument("--server", default="http://127.0.0.1:47770")
    ap.add_argument("--language", default=None)
    ap.add_argument("--backend", choices=["pulse", "alsa"], default="pulse")
    ap.add_argument("--device", default="default")
    ap.add_argument("--rate", type=int, default=16000)
    ap.add_argument("--channels", type=int, default=1)

    # Modes
    ap.add_argument("--stream", action="store_true", help="Streaming mode")
    ap.add_argument("--batch", action="store_true", help="Batch mode")

    # VAD / segmentation knobs
    ap.add_argument("--vad-level", type=int, default=2)
    ap.add_argument("--frame-ms", type=int, default=30)
    ap.add_argument("--silence-ms", type=int, default=600)
    ap.add_argument("--pre-roll-ms", type=int, default=200)
    ap.add_argument("--max-utterance-ms", type=int, default=30000)
    ap.add_argument(
        "--min-seconds",
        type=float,
        default=0.8,
        help="Minimum utterance length (seconds) to send to Whisper",
    )
    ap.add_argument(
        "--segment-dir",
        default=None,
        help="If set, save each segment WAV here for debugging",
    )

    # Whisper server passthrough + context
    ap.add_argument(
        "--whisper-arg",
        action="append",
        default=[],
        help="Extra form fields key=value passed to server",
    )
    ap.add_argument(
        "--context-chars",
        type=int,
        default=500,
        help="How many trailing characters of prior text to feed as initial_prompt",
    )
    ap.add_argument(
        "--chunk-sep",
        default=" ",
        help="String printed between chunks (default single space)",
    )

    # PID
    ap.add_argument(
        "--pidfile",
        default=os.path.join(
            os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"), "stt-rec.pid"
        ),
    )

    args = ap.parse_args()

    if not args.stream and not args.batch:
        args.stream = True

    os.makedirs(os.path.dirname(args.pidfile), exist_ok=True)
    with open(args.pidfile, "w") as f:
        f.write(str(os.getpid()))

    extra_fields: List[Tuple[str, str]] = []
    for kv in args.whisper_arg:
        if "=" in kv:
            k, v = kv.split("=", 1)
            extra_fields.append((k.strip(), v.strip()))
        else:
            extra_fields.append((kv.strip(), "true"))

    terminate_flag = False

    def on_sigint(signum, frame):
        nonlocal terminate_flag
        terminate_flag = True
        sys.stderr.write("[stt] SIGINT received, shutting down.\n")
        sys.stderr.flush()

    signal.signal(signal.SIGINT, on_sigint)

    try:
        if args.stream:
            # mic -> ffmpeg -> raw s16le -> VAD -> segments -> upload
            cmd = (
                ["ffmpeg", "-loglevel", "quiet"]
                + ffmpeg_input_cmd(args.backend, args.device)
                + [
                    "-ac",
                    "1",
                    "-ar",
                    str(args.rate),
                    "-af",
                    "highpass=f=80,lowpass=f=8000",
                    "-f",
                    "s16le",
                    "pipe:1",
                ]
            )
            proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, preexec_fn=os.setsid)
            assert proc.stdout is not None

            seg = VADSegmenter(
                sample_rate=args.rate,
                frame_ms=args.frame_ms,
                vad_level=args.vad_level,
                silence_ms=args.silence_ms,
                pre_roll_ms=args.pre_roll_ms,
                max_utterance_ms=args.max_utterance_ms,
            )

            last_text = ""  # accumulate context across chunks
            printed_so_far = ""  # for dedup/overlap trimming in output

            def upload_segment(frames: List[bytes]) -> Optional[str]:
                nonlocal last_text, printed_so_far

                duration = len(frames) * (seg.frame_ms / 1000.0)
                if duration < args.min_seconds:
                    # Skip trivial/near-silent chunks to avoid hallucinations
                    sys.stderr.write(
                        f"[stt] Skipping short utterance ({duration:.2f}s)\n"
                    )
                    sys.stderr.flush()
                    return None

                wav_bytes = write_wav(frames, args.rate)
                with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tf:
                    tf.write(wav_bytes)
                    tf.flush()

                    fields = list(extra_fields)
                    # Always feed context for coherence
                    if args.context_chars > 0 and last_text.strip():
                        fields.append(
                            ("initial_prompt", last_text[-args.context_chars :])
                        )

                    raw = upload_file_curl(args.server, tf.name, args.language, fields)

                with contextlib.suppress(Exception):
                    os.unlink(tf.name)

                if raw is None:
                    return None  # error already logged to stderr

                text = extract_text_from_json(raw).strip()

                # Guard against common tiny hallucinations
                if not text or text.lower() in {
                    "thank you.",
                    "thank you",
                    ".",
                    "ok.",
                    "okay.",
                    "internal server error",
                }:
                    return None

                # Deduplicate: only emit the delta relative to what we've printed so far
                overlap = longest_overlap_suffix_prefix(printed_so_far, text)
                delta = text[overlap:].lstrip()
                if not delta:
                    return None

                # Output as flowing paragraph (default chunk separator is a space)
                # You can switch to "\n" if you want line-per-chunk.
                sys.stdout.write((args.chunk_sep if printed_so_far else "") + delta)
                sys.stdout.flush()

                printed_so_far += delta
                last_text += (
                    " " if last_text and not last_text.endswith(" ") else ""
                ) + delta
                return text

            chunk_bytes = seg.frame_bytes * 20  # ~20 frames per read
            while not terminate_flag:
                chunk = proc.stdout.read(chunk_bytes)
                if not chunk:
                    # Avoid busy loop; also prevents accidental uploads on pure silence
                    time.sleep(0.05)
                    continue
                for utt in seg.push(chunk):
                    upload_segment(utt)

            # Flush any tail
            rem = seg.flush()
            if rem:
                upload_segment(rem)

        else:
            # Batch record then upload once
            wav_path = os.path.join(tempfile.gettempdir(), "stt_record.wav")
            cmd = (
                ["ffmpeg", "-loglevel", "quiet"]
                + ffmpeg_input_cmd(args.backend, args.device)
                + [
                    "-ac",
                    str(args.channels),
                    "-ar",
                    str(args.rate),
                    "-c:a",
                    "pcm_s16le",
                    "-y",
                    wav_path,
                ]
            )
            proc = subprocess.Popen(cmd, preexec_fn=os.setsid)

            def on_sigint_batch(s, f):
                with contextlib.suppress(Exception):
                    os.killpg(os.getpgid(proc.pid), signal.SIGTERM)

            signal.signal(signal.SIGINT, on_sigint_batch)

            proc.wait()

            raw = upload_file_curl(args.server, wav_path, args.language, extra_fields)
            with contextlib.suppress(Exception):
                os.unlink(wav_path)
            if raw is not None:
                text = extract_text_from_json(raw).strip()
                if text:
                    # In batch, print the full paragraph followed by newline
                    print(text, flush=True)

    except Exception as e:
        # Keep stdout clean for piping; log problems here
        sys.stderr.write(f"[stt] {e}\n")
        sys.stderr.flush()
    finally:
        with contextlib.suppress(Exception):
            os.remove(args.pidfile)


if __name__ == "__main__":
    main()
