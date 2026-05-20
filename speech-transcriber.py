#!/usr/bin/env python3
import os
import tempfile
from pathlib import Path

from fastapi import FastAPI, File, UploadFile
from openai import OpenAI

app = FastAPI(title="Shared Speech Transcriber")


@app.get("/health")
def health():
    return {
        "status": "ok",
        "model": os.environ.get("OPENAI_TRANSCRIPTION_MODEL", "gpt-4o-transcribe"),
        "api_key_configured": bool(os.environ.get("OPENAI_API_KEY")),
    }


@app.post("/v1/transcribe")
async def transcribe(file: UploadFile = File(...)):
    model = os.environ.get("OPENAI_TRANSCRIPTION_MODEL", "gpt-4o-transcribe")
    language = os.environ.get("OPENAI_TRANSCRIPTION_LANGUAGE", "ru")
    prompt = os.environ.get("OPENAI_TRANSCRIPTION_PROMPT", "")
    suffix = Path(file.filename or "audio.ogg").suffix or ".ogg"
    if suffix in (".oga", ".opus"):
        suffix = ".ogg"

    data = await file.read()
    with tempfile.NamedTemporaryFile(suffix=suffix, delete=False) as tmp:
        tmp.write(data)
        path = tmp.name
    try:
        client = OpenAI()
        with open(path, "rb") as audio:
            result = client.audio.transcriptions.create(
                model=model,
                file=audio,
                language=language,
                prompt=prompt or None,
            )
        return {
            "text": result.text,
            "model": model,
            "language": language,
            "bytes": len(data),
            "filename": file.filename,
        }
    finally:
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass

