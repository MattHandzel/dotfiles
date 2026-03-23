from __future__ import annotations

import asyncio
import logging
import time
from typing import TYPE_CHECKING

from faster_whisper.vad import VadOptions, get_speech_timestamps

from faster_whisper_server.api_models import TranscriptionSegment, TranscriptionWord
from faster_whisper_server.text_utils import Transcription

if TYPE_CHECKING:
    from faster_whisper import transcribe

    from faster_whisper_server.audio import Audio

logger = logging.getLogger(__name__)

EMPTY_VAD_OPTIONS = VadOptions()
EMPTY_LANGUAGE_DETECTION_ERROR = "max() iterable argument is empty"


class FasterWhisperASR:
    def __init__(
        self,
        whisper: transcribe.WhisperModel,
        **kwargs,
    ) -> None:
        self.whisper = whisper
        self.transcribe_opts = kwargs

    def _transcribe(
        self,
        audio: Audio,
        prompt: str | None = None,
    ) -> tuple[Transcription, transcribe.TranscriptionInfo | None]:
        if audio.data.size == 0:
            logger.info("Skipping an empty audio chunk.")
            return (Transcription(), None)

        if self.transcribe_opts.get("vad_filter") and len(get_speech_timestamps(audio.data, EMPTY_VAD_OPTIONS)) == 0:
            logger.info("Skipping an audio chunk with no speech after VAD.")
            return (Transcription(), None)

        start = time.perf_counter()
        try:
            segments, transcription_info = self.whisper.transcribe(
                audio.data,
                initial_prompt=prompt,
                word_timestamps=True,
                **self.transcribe_opts,
            )
        except ValueError as exc:
            if str(exc) == EMPTY_LANGUAGE_DETECTION_ERROR:
                logger.info("Skipping a too-short or speechless audio chunk.")
                return (Transcription(), None)
            raise

        segments = TranscriptionSegment.from_faster_whisper_segments(segments)
        words = TranscriptionWord.from_segments(segments)
        for word in words:
            word.offset(audio.start)
        transcription = Transcription(words)
        end = time.perf_counter()
        logger.info(
            f"Transcribed {audio} in {end - start:.2f} seconds. Prompt: {prompt}. Transcription: {transcription.text}"
        )
        return (transcription, transcription_info)

    async def transcribe(
        self,
        audio: Audio,
        prompt: str | None = None,
    ) -> tuple[Transcription, transcribe.TranscriptionInfo | None]:
        return await asyncio.get_running_loop().run_in_executor(
            None,
            self._transcribe,
            audio,
            prompt,
        )
