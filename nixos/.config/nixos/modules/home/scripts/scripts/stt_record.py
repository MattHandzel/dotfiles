#!/usr/bin/env python3
import argparse
import json
import os
import signal
import subprocess
import sys
import tempfile


def notify(summary, body=None, urgency="low"):
    subprocess.run(
        ["notify-send", "-u", urgency, "-t", "1000", summary]
        + ([body] if body else []),
        check=False,
    )


def run_ffmpeg(device: str, rate: int, channels: int, outfile: str):
    return subprocess.Popen(
        [
            "ffmpeg",
            "-loglevel",
            "quiet",
            "-f",
            "alsa",
            "-i",
            device,
            "-ac",
            str(channels),
            "-ar",
            str(rate),
            "-c:a",
            "pcm_s16le",
            "-y",
            outfile,
        ]
    )


def upload_raw(server_url: str, audio_path: str, language: str | None):
    url = f"{server_url.rstrip('/')}/v1/audio/transcriptions"
    cmd = ["curl", "-sS", url, "-F", f"file=@{audio_path}"]
    if language:
        cmd += ["-F", f"language={language}"]
    return subprocess.check_output(cmd)


def extract_text_from_json(raw_bytes: bytes) -> str:
    try:
        data = json.loads(raw_bytes.decode("utf-8", errors="replace"))
        if isinstance(data, dict):
            if isinstance(data.get("text"), str):
                return data["text"]
            if isinstance(data.get("transcript"), str):
                return data["transcript"]
            if isinstance(data.get("segments"), list):
                return "".join(seg.get("text", "") for seg in data["segments"])
    except json.JSONDecodeError:
        pass
    return raw_bytes.decode("utf-8", errors="replace")


def type_with_wtype(text: str, delay_ms: int = 0):
    return (
        subprocess.run(
            ["wtype", "-d", str(delay_ms), "-"], input=text.encode("utf-8")
        ).returncode
        == 0
    )


def copy_with_wlcopy(text: str):
    p = subprocess.run(["wl-copy"], input=text.encode("utf-8"))
    return p.returncode == 0


def main():
    ap = argparse.ArgumentParser(
        description="Record until SIGINT, upload to faster-whisper-server, print raw response; type or copy the transcript."
    )
    ap.add_argument(
        "--server",
        default="http://192.168.0.8:47770",
        help="Base URL, e.g. http://host:port",
    )
    ap.add_argument(
        "--device",
        default="default",
        help="ALSA input device for ffmpeg (-f alsa -i DEVICE)",
    )
    ap.add_argument("--rate", type=int, default=16000)
    ap.add_argument("--channels", type=int, default=1)
    ap.add_argument(
        "--outfile", default=None, help="Output WAV path (default: temp file)"
    )
    ap.add_argument(
        "--pidfile",
        default=os.path.join(
            os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"), "stt-rec.pid"
        ),
    )
    ap.add_argument("--language", default=None, help="Language hint, e.g. en, es, pl")
    ap.add_argument(
        "--mode",
        choices=["type", "clipboard"],
        default="type",
        help="Action after upload: type into focused window or copy to clipboard",
    )
    ap.add_argument(
        "--type-delay-ms",
        type=int,
        default=1,
        help="Inter-key delay for wtype in 'type' mode",
    )
    args = ap.parse_args()

    wav_path = args.outfile or os.path.join(tempfile.gettempdir(), "stt_record.wav")
    os.makedirs(os.path.dirname(args.pidfile), exist_ok=True)
    with open(args.pidfile, "w") as f:
        f.write(str(os.getpid()))

    notify("STT", f"Recording… Mode: {args.mode}", "low")
    proc = run_ffmpeg(args.device, args.rate, args.channels, wav_path)

    def handle_sigint(signum, frame):
        try:
            proc.send_signal(signal.SIGINT)
        except Exception:
            pass

    signal.signal(signal.SIGINT, handle_sigint)

    try:
        proc.wait()
    finally:
        if proc.poll() is None:
            try:
                proc.terminate()
            except Exception:
                pass

    try:
        notify("STT", "Uploading and transcribing…", "low")
        raw = upload_raw(args.server, wav_path, args.language)
        # Always print raw server response (stdout)
        sys.stdout.buffer.write(raw)
        sys.stdout.flush()

        # Parse text for post-action
        text = extract_text_from_json(raw).strip()

        ok = True
        if args.mode == "type":
            ok = type_with_wtype(text, delay_ms=args.type_delay_ms)
        elif args.mode == "clipboard":
            ok = copy_with_wlcopy(text)

        notify(
            "STT",
            (
                "Transcription complete"
                if ok
                else "Transcription done (post-action failed)"
            ),
            "normal",
        )
    except subprocess.CalledProcessError as e:
        sys.stderr.write(e.output.decode("utf-8", errors="replace"))
        sys.stderr.flush()
        notify("STT Error", "Upload/transcription failed", "critical")
        raise
    finally:
        try:
            os.remove(args.pidfile)
        except Exception:
            pass


if __name__ == "__main__":
    main()
