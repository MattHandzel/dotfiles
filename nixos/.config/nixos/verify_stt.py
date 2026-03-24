import os
import sys
import time
import subprocess
import io
import requests

# Verification Script for STT Pipeline
# Usage: /home/matth/.venvs/stt/bin/python verify_stt.py

SERVER = "http://server.matthandzel.com:47770"
RATE = 16000

_SESSION = requests.Session()

def ffmpeg_compress(wav_bytes: bytes, rate: int) -> bytes:
    cmd = [
        "ffmpeg", "-loglevel", "error", "-y",
        "-f", "s16le", "-ar", str(rate), "-ac", "1", "-i", "-",
        "-c:a", "libopus", "-b:a", "32k", "-f", "opus", "-"
    ]
    res = subprocess.run(cmd, input=wav_bytes, capture_output=True, check=True)
    return res.stdout

def upload_file_persistent(server_url, audio_bytes, filename, extra_fields):
    url = f"{server_url.rstrip('/')}/v1/audio/transcriptions"
    files = {'file': (filename, audio_bytes)}
    data = dict(extra_fields)
    response = _SESSION.post(url, files=files, data=data, timeout=10)
    return response

print("Generating dummy audio...")
dummy_pcm = os.getrandom(96000) 

print("Testing in-memory Opus compression...")
start_comp = time.time()
compressed = ffmpeg_compress(dummy_pcm, RATE)
comp_time = time.time() - start_comp
print(f"Compressed {len(dummy_pcm)} bytes to {len(compressed)} bytes in {comp_time:.3f}s")

print(f"Testing persistent upload to {SERVER}...")
extra = [("initial_prompt", "Verification test."), ("save_training_data", "true")]
start_up = time.time()
resp = upload_file_persistent(SERVER, compressed, "test.opus", extra)
up_time = time.time() - start_up

print(f"Server Response Code: {resp.status_code}")
print(f"Upload + Inference Time: {up_time:.3f}s")
if resp.status_code == 200:
    print(f"Transcript: {resp.json().get('text', 'No text returned')}")
else:
    print(f"Error Body: {resp.text}")

print("Testing second upload (verifying warm connection)...")
start_up2 = time.time()
resp2 = upload_file_persistent(SERVER, compressed, "test2.opus", extra)
up_time2 = time.time() - start_up2
print(f"Second Upload Time: {up_time2:.3f}s")
print(f"Connection warm-up saving: {up_time - up_time2:.3f}s")
