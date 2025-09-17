#!/usr/bin/env python3
import argparse
import os
import signal
import subprocess
import sys
import tempfile


def notify(summary, body=None, urgency="low"):
    cmd = ["notify-send", "-u", urgency, summary]
    if body:
        cmd.append(body)
    subprocess.run(cmd, check=False)


def run_ffmpeg(device: str, rate: int, channels: int, outfile: str):
    # ALSA -> 16kHz mono PCM WAV
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


def main():
    ap = argparse.ArgumentParser(
        description="Record until SIGINT, upload to faster-whisper-server, print raw response."
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
    args = ap.parse_args()

    # Prepare output file and pidfile
    wav_path = args.outfile or os.path.join(tempfile.gettempdir(), "stt_record.wav")
    os.makedirs(os.path.dirname(args.pidfile), exist_ok=True)
    with open(args.pidfile, "w") as f:
        f.write(str(os.getpid()))

    # Start recording
    notify("STT", "Recording… Press Mod+S again to stop", "low")
    proc = run_ffmpeg(args.device, args.rate, args.channels, wav_path)

    def handle_sigint(signum, frame):
        try:
            proc.send_signal(signal.SIGINT)
        except Exception:
            pass

    signal.signal(signal.SIGINT, handle_sigint)

    # Wait until interrupted (toggle sends SIGINT)
    try:
        proc.wait()
    finally:
        # Ensure recorder is not left dangling
        if proc.poll() is None:
            try:
                proc.terminate()
            except Exception:
                pass

    # Upload and print raw server response
    try:
        sys.stdout.flush()
        raw = upload_raw(args.server, wav_path, args.language)
        sys.stdout.buffer.write(raw)
        sys.stdout.flush()
        notify("STT", "Transcription complete", "normal")
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
