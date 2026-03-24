#!/home/matth/.venvs/stt/bin/python
# -*- coding: utf-8 -*-

# NOTE: If there any errors with this script (some mismatch) then it is because the venv in ~/.venvs/... is not working. Run `cd ~/.venvs/stt && ns -p python3Packages.pip --run "bin/pip install webrtcvad "

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
import threading
import queue
from typing import Callable, Deque, List, Tuple, Optional

import webrtcvad


# VERIFICATION: You can verify the integrity and performance of this pipeline by running:
# /home/matth/.venvs/stt/bin/python /home/matth/dotfiles/nixos/.config/nixos/verify_stt.py

import requests

# ----------------------- Helpers -----------------------

def notify_error(msg: str):
    try:
        subprocess.run(["notify-send", "-u", "critical", "-t", "5000", "🎙 STT Error", msg], check=False)
    except Exception:
        pass

# Global session for persistent connections (Zero-Handshake)
_SESSION = requests.Session()

def upload_file_persistent(
    server_url: str,
    audio_bytes: bytes,
    filename: str,
    language: Optional[str],
    extra_fields: List[Tuple[str, str]],
) -> Optional[bytes]:
    """
    Upload audio using a persistent HTTP session to minimize RTT overhead.
    """
    url = f"{server_url.rstrip('/')}/v1/audio/transcriptions"
    
    data = {}
    if language:
        data['language'] = language
    for k, v in extra_fields:
        data[k] = v
    
    # Request the server to save this segment for future fine-tuning
    data['save_training_data'] = 'true'

    max_retries = 3
    for attempt in range(1, max_retries + 1):
        try:
            ts = time.strftime('%H:%M:%S')
            files = {'file': (filename, audio_bytes)}
            # Using a timeout to prevent hanging, but keeping it generous for inference
            response = _SESSION.post(url, files=files, data=data, timeout=30)
            
            if response.status_code == 500:
                msg = "Server returned 500 Error. Aborting STT."
                sys.stderr.write(f"[stt] {ts} Server returned 500: {response.text[:200]}\n")
                notify_error(msg)
                raise RuntimeError("Server 500 Error")
            elif response.status_code != 200:
                msg = f"Server returned {response.status_code}"
                sys.stderr.write(f"[stt] {ts} {msg}: {response.text[:200]}\n")
                if attempt == max_retries:
                    notify_error(f"Upload failed after {max_retries} attempts: {msg}")
                    return None
                time.sleep(1)
                continue
            
            return response.content
        except requests.exceptions.RequestException as e:
            ts = time.strftime('%H:%M:%S')
            sys.stderr.write(f"[stt] {ts} Upload error: {e}\n")
            if attempt == max_retries:
                notify_error(f"Upload failed after {max_retries} attempts: {type(e).__name__}")
                return None
            time.sleep(1)
            
    return None

def ffmpeg_compress(wav_bytes: bytes, rate: int) -> bytes:
    """Compress PCM to Opus in-memory using ffmpeg."""
    cmd = [
        "ffmpeg", "-loglevel", "error", "-y",
        "-f", "s16le", "-ar", str(rate), "-ac", "1", "-i", "-",
        "-c:a", "libopus", "-b:a", "32k", "-f", "opus", "-"
    ]
    try:
        res = subprocess.run(cmd, input=wav_bytes, capture_output=True, check=True)
        return res.stdout
    except Exception as e:
        sys.stderr.write(f"[stt] Compression failed: {e}\n")
        return wav_bytes # Fallback to raw (unlikely to work if server expects format, but better than nothing)


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
        speech_state_cb: Optional[Callable[[bool], None]] = None,
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
        self.speech_state_cb = speech_state_cb
        self._speaking = False

        self.reset()

    def _set_speaking(self, speaking: bool):
        if self._speaking == speaking:
            return
        self._speaking = speaking
        if self.speech_state_cb is not None:
            try:
                self.speech_state_cb(speaking)
            except Exception:
                pass

    def reset(self):
        self._set_speaking(False)
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
                    self._set_speaking(True)
                    sys.stderr.write(f"[stt] {time.strftime('%H:%M:%S')} Speech detected, recording...\n")
                    sys.stderr.flush()
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
                    reason = "silence" if self.silence_run >= self.silence_frames_needed else "timeout"
                    sys.stderr.write(f"[stt] {time.strftime('%H:%M:%S')} Utterance complete ({reason})\n")
                    sys.stderr.flush()
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
    ap.add_argument(
        "--paste",
        action="store_true",
        help="Paste each chunk live using wl-copy and wtype",
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
        "--prompt",
        type=str,
        default="",
        help="Initial prompt to guide transcription",
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
    ap.add_argument(
        "--status-file",
        default=None,
        help="Optional Waybar JSON status file for STT mic indicator",
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

    def write_status(class_name: str, tooltip: str):
        if not args.status_file:
            return
        try:
            os.makedirs(os.path.dirname(args.status_file), exist_ok=True)
            with open(args.status_file, "w", encoding="utf-8") as f:
                json.dump({"text": "", "class": [class_name], "tooltip": tooltip}, f)
                f.write("\n")
        except Exception:
            pass

    def on_sigint(signum, frame):
        nonlocal terminate_flag
        terminate_flag = True
        sys.stderr.write("[stt] SIGINT received, shutting down.\n")
        sys.stderr.flush()

    signal.signal(signal.SIGINT, on_sigint)

    try:
        ts = time.strftime('%H:%M:%S')
        sys.stderr.write(f"[stt] {ts} Starting session (server={args.server}, device={args.device})\n")
        sys.stderr.flush()
        write_status("active", "STT listening")

        if args.stream:
            # mic -> ffmpeg -> raw s16le -> VAD -> segments -> upload
            # Use 'info' or 'warning' instead of 'quiet' for better observability in logs
            cmd = (
                ["ffmpeg", "-loglevel", "warning"]
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
            # We don't redirect stderr here so it goes to the parent's stderr (LOGFILE)
            proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, preexec_fn=os.setsid)
            assert proc.stdout is not None

            # Register cleanup for this process
            def cleanup_proc():
                if proc.poll() is None:
                    with contextlib.suppress(Exception):
                        os.killpg(os.getpgid(proc.pid), signal.SIGTERM)
            
            # Ensure we kill ffmpeg on SIGINT
            original_sigint = signal.getsignal(signal.SIGINT)
            def on_sigint_stream(signum, frame):
                nonlocal terminate_flag
                terminate_flag = True
                sys.stderr.write("[stt] SIGINT received, shutting down.\n")
                cleanup_proc()
            signal.signal(signal.SIGINT, on_sigint_stream)

            seg = VADSegmenter(
                sample_rate=args.rate,
                frame_ms=args.frame_ms,
                vad_level=args.vad_level,
                silence_ms=args.silence_ms,
                pre_roll_ms=args.pre_roll_ms,
                max_utterance_ms=args.max_utterance_ms,
                speech_state_cb=lambda speaking: write_status(
                    "speaking" if speaking else "active",
                    "STT speaking" if speaking else "STT listening",
                ),
            )
            
            # Threaded upload worker setup
            upload_q = queue.Queue()
            
            # Shared state for the worker
            state = {
                "last_text": "",
                "printed_so_far": ""
            }

            def upload_worker():
                while True:
                    item = upload_q.get()
                    if item is None:
                        upload_q.task_done()
                        break
                    
                    frames, is_final = item
                    
                    duration = len(frames) * (seg.frame_ms / 1000.0)
                    ts = time.strftime('%H:%M:%S')
                    if not is_final and duration < args.min_seconds:
                        # Skip trivial/near-silent chunks to avoid hallucinations
                        sys.stderr.write(
                            f"[stt] {ts} Skipping short utterance ({duration:.2f}s < {args.min_seconds}s)\n"
                        )
                        sys.stderr.flush()
                        upload_q.task_done()
                        continue

                    sys.stderr.write(f"[stt] {ts} Uploading segment ({duration:.2f}s)...\n")
                    sys.stderr.flush()

                    wav_bytes = write_wav(frames, args.rate)
                    # Master of Performance: In-memory compression and persistent session
                    audio_payload = ffmpeg_compress(wav_bytes, args.rate)
                    
                    fields = list(extra_fields)
                    # Always feed context for coherence
                    context = args.prompt + ". " + state["last_text"][-args.context_chars + 2 + len(args.prompt) :]
                    fields.append(("initial_prompt", context))

                    # Use the persistent session to avoid DNS/TCP/TLS overhead (saves ~230ms per chunk)
                    try:
                        raw = upload_file_persistent(args.server, audio_payload, "audio.opus", args.language, fields)
                    except RuntimeError as e:
                        if "Server 500 Error" in str(e):
                            os.kill(os.getpid(), signal.SIGINT)
                        upload_q.task_done()
                        continue

                    if raw is None:
                        sys.stderr.write(f"[stt] {ts} Upload failed\n")
                        sys.stderr.flush()
                        upload_q.task_done()
                        continue

                    text = extract_text_from_json(raw).strip()
                    
                    # Remove trailing periods as requested by the user
                    text = text.rstrip(".")

                    # Guard against common tiny hallucinations and noise artifacts
                    hallucinations = {
                        "thank you.",
                        "thank you",
                        ".",
                        "...",
                        "ok.",
                        "okay.",
                        "internal server error",
                        "hmm.",
                        "hmm",
                        "hmmm.",
                        "hmmm",
                        "uh.",
                        "uh",
                        "um.",
                        "um",
                        "you",
                        "re",
                        "i'm sorry",
                        "i am sorry",
                        "sorry",
                    }
                    if not text:
                        sys.stderr.write(f"[stt] {ts} Received empty transcript\n")
                        sys.stderr.flush()
                        upload_q.task_done()
                        continue
                    
                    if text.lower() in hallucinations or len(text) <= 1:
                        sys.stderr.write(f"[stt] {ts} Filtered out hallucination/noise: \"{text}\"\n")
                        sys.stderr.flush()
                        upload_q.task_done()
                        continue

                    # For VAD-separated chunks, we generally don't want overlap deduplication
                    # as it prevents repeating the same word. If the server is OpenAI-compatible 
                    # /v1/audio/transcriptions, it usually only returns the text for the audio sent.
                    delta = text

                    sys.stderr.write(f"[stt] {ts} Received: \"{text}\"\n")
                    sys.stderr.flush()

                    # Output as flowing paragraph (default chunk separator is a space)
                    sys.stdout.write(delta + args.chunk_sep)
                    sys.stdout.flush()

                    if args.paste:
                        try:
                            # Use wtype to type the text directly via stdin.
                            # We include the chunk separator to keep spacing correct between utterances.
                            to_type = delta + args.chunk_sep
                            subprocess.run(["wtype", "-"], input=to_type.encode("utf-8"), check=True)
                        except Exception as pe:
                            sys.stderr.write(f"[stt] {ts} Type failed: {pe}\n")
                            sys.stderr.flush()

                    state["printed_so_far"] += delta
                    state["last_text"] += (
                        " " if state["last_text"] and not state["last_text"].endswith(" ") else ""
                    ) + delta
                    
                    upload_q.task_done()

            # Start the worker thread
            t = threading.Thread(target=upload_worker, daemon=True)
            t.start()

            chunk_bytes = seg.frame_bytes * 20  # ~20 frames per read
            
            try:
                while not terminate_flag:
                    chunk = proc.stdout.read(chunk_bytes)
                    if not chunk:
                        # ffmpeg exited or stream closed
                        if not terminate_flag:
                            sys.stderr.write("[stt] ffmpeg stream closed unexpectedly.\n")
                            notify_error("Microphone disconnected or ffmpeg failed.")
                        break
                    for utt in seg.push(chunk):
                        upload_q.put((utt, False))

                # Flush any tail
                rem = seg.flush()
                if rem:
                    upload_q.put((rem, True))
            finally:
                cleanup_proc()
                # Signal worker to stop and wait for it
                sys.stderr.write(f"[stt] Waiting for uploads to complete...\n")
                upload_q.put(None)
                t.join()


        else:
            # Batch record then upload once
            wav_path = os.path.join(tempfile.gettempdir(), "stt_record.wav")
            cmd = (
                ["ffmpeg", "-loglevel", "warning"]
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

            with open(wav_path, "rb") as f:
                wav_bytes = f.read()
            
            # Compress and upload using the same high-performance pipeline
            audio_payload = ffmpeg_compress(wav_bytes, args.rate)
            try:
                raw = upload_file_persistent(args.server, audio_payload, "audio.opus", args.language, extra_fields)
            except RuntimeError:
                raw = None
            
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
        notify_error(f"Fatal error: {e}")
    finally:
        write_status("off", "STT off (click to toggle live)")
        with contextlib.suppress(Exception):
            os.remove(args.pidfile)


if __name__ == "__main__":
    main()
