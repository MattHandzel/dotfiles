import os
import subprocess
import torch
import tempfile
import re
from fastapi import FastAPI, UploadFile, File, Form, HTTPException
from fastapi.responses import JSONResponse
from typing import Optional

# NeMo and related imports
from nemo.collections.speechlm2.models import SALM
from transformers import AutoTokenizer

app = FastAPI(title="NVIDIA Canary-Qwen SOTA STT Server", version="1.7")

# --- Global Model Variables ---
canary_model = None

def clean_chatml(text: str) -> str:
    """Robustly strip ChatML prompt and assistant markers."""
    if "<|im_start|>assistant" in text:
        text = text.split("<|im_start|>assistant")[-1]
    text = re.sub(r"<\|.*?\|>", "", text)
    text = re.sub(r"^(Text|Transcript|Corrected Text|Transcript segment):\s*", "", text, flags=re.IGNORECASE | re.MULTILINE)
    return text.strip()


def normalize_audio(upload: UploadFile) -> tuple[str, str]:
    suffix = os.path.splitext(upload.filename or "")[1] or ".bin"
    with tempfile.NamedTemporaryFile(suffix=suffix, delete=False) as src_file:
        src_path = src_file.name

    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as wav_file:
        wav_path = wav_file.name

    return src_path, wav_path


def split_audio(audio_path: str, segment_seconds: int) -> list[str]:
    if segment_seconds <= 0:
        return [audio_path]

    segments_dir = tempfile.mkdtemp(prefix="canary-segments-")
    segment_pattern = os.path.join(segments_dir, "chunk_%03d.wav")
    subprocess.run(
        [
            "ffmpeg",
            "-y",
            "-i",
            audio_path,
            "-f",
            "segment",
            "-segment_time",
            str(segment_seconds),
            "-c",
            "copy",
            segment_pattern,
        ],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    segments = sorted(
        os.path.join(segments_dir, name)
        for name in os.listdir(segments_dir)
        if name.endswith(".wav")
    )
    return segments or [audio_path]


def transcribe_segment(audio_path: str) -> str:
    transcription_prompt = [
        [{"role": "user", "content": f"Transcribe the following: {canary_model.audio_locator_tag}", "audio": [audio_path]}]
    ]

    with torch.no_grad():
        answer_ids = canary_model.generate(
            prompts=transcription_prompt,
            max_new_tokens=192,
            repetition_penalty=1.2,
            temperature=0.0,
            do_sample=False,
        )

    return clean_chatml(canary_model.tokenizer.ids_to_text(answer_ids[0].cpu()))


def polish_transcript(text: str) -> str:
    polishing_prompt = [
        [{"role": "user", "content": (
            "Lightly clean this transcript for punctuation and capitalization only. "
            "Do not add facts. Do not paraphrase. Do not translate. Output only corrected transcript.\n\n"
            f"Transcript: {text}"
        )}]
    ]
    with torch.no_grad():
        polished_ids = canary_model.generate(
            prompts=polishing_prompt,
            max_new_tokens=256,
            repetition_penalty=1.1,
            temperature=0.0,
            do_sample=False,
        )
    return clean_chatml(canary_model.tokenizer.ids_to_text(polished_ids[0].cpu()))

@app.on_event("startup")
async def startup_event():
    global canary_model
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    base_path = "/models/hub/models--nvidia--canary-qwen-2.5b/snapshots/6cfc37ec7edc35a0545c403f551ecdfa28133d72"
    print(f"[INIT] Loading Canary-Qwen SOTA v1.7 from {base_path}...", flush=True)
    canary_model = SALM.from_pretrained(base_path)
    canary_model.eval()
    if device.type == "cuda":
        canary_model.bfloat16()
    canary_model.to(device)
    print(f"[INIT] Server Ready on Port 47770 using device={device}", flush=True)

@app.post("/v1/audio/transcriptions")
async def transcribe_audio(
    file: UploadFile = File(...),
    language: Optional[str] = Form("en"),
    prompt: Optional[str] = Form(""),
    segment_seconds: int = Form(30),
    postprocess: bool = Form(False),
):
    audio_path = None
    src_path = None
    segment_paths: list[str] = []
    try:
        src_path, audio_path = normalize_audio(file)
        with open(src_path, "wb") as tmp_file:
            tmp_file.write(await file.read())

        # Force a clean 16 kHz mono WAV so mobile recordings like .m4a decode reliably.
        subprocess.run(
            [
                "ffmpeg",
                "-y",
                "-i",
                src_path,
                "-ac",
                "1",
                "-ar",
                "16000",
                audio_path,
            ],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )

        segment_paths = split_audio(audio_path, segment_seconds)
        chunk_texts = []
        for segment_path in segment_paths:
            chunk_text = transcribe_segment(segment_path)
            if chunk_text:
                chunk_texts.append(chunk_text)

        predicted_text = " ".join(chunk_texts).strip()
        final_text = polish_transcript(predicted_text) if postprocess and len(predicted_text.split()) > 3 else predicted_text

        return JSONResponse(content={"text": final_text})

    except Exception as e:
        print(f"[ERROR] {str(e)}", flush=True)
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        for path in (src_path, audio_path):
            if path and os.path.exists(path):
                os.remove(path)
        for segment_path in segment_paths:
            if segment_path != audio_path and os.path.exists(segment_path):
                os.remove(segment_path)
        if segment_paths:
            segments_dir = os.path.dirname(segment_paths[0])
            if os.path.isdir(segments_dir) and os.path.basename(segments_dir).startswith("canary-segments-"):
                try:
                    os.rmdir(segments_dir)
                except OSError:
                    pass

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=47770)
