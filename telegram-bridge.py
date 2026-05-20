#!/usr/bin/env python3
import html
import json
import os
import subprocess
import tempfile
import time
import urllib.parse
import urllib.request

TOKEN = os.environ["TELEGRAM_BOT_TOKEN"]
OWNER = os.environ.get("TELEGRAM_OWNER_CHAT_ID", "").strip()
CODEX_USER = os.environ.get("CODEX_USER", os.environ.get("USER", ""))
CODEX_WORKDIR = os.environ.get("CODEX_WORKDIR", os.path.expanduser("~/GIT"))
TRANSCRIBE_URL = os.environ.get("TRANSCRIBE_URL", "http://127.0.0.1:8765/v1/transcribe")
API = f"https://api.telegram.org/bot{TOKEN}"


def api(method, data=None):
    body = None
    headers = {}
    if data is not None:
        body = urllib.parse.urlencode(data).encode()
        headers["Content-Type"] = "application/x-www-form-urlencoded"
    req = urllib.request.Request(f"{API}/{method}", data=body, headers=headers)
    with urllib.request.urlopen(req, timeout=60) as resp:
        return json.loads(resp.read().decode())


def send(chat_id, text):
    api("sendMessage", {
        "chat_id": chat_id,
        "text": text[:3900],
        "parse_mode": "HTML",
        "disable_web_page_preview": "true",
    })


def allowed(chat_id):
    return not OWNER or str(chat_id) == OWNER


def run_shell(command):
    return subprocess.run(
        command,
        shell=True,
        cwd=CODEX_WORKDIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=900,
    ).stdout


def run_codex(prompt):
    cmd = [
        "sudo", "-H", "-u", CODEX_USER,
        "codex", "exec",
        "--dangerously-bypass-approvals-and-sandbox",
        "--skip-git-repo-check",
        "-C", CODEX_WORKDIR,
        prompt,
    ] if CODEX_USER else [
        "codex", "exec",
        "--dangerously-bypass-approvals-and-sandbox",
        "--skip-git-repo-check",
        "-C", CODEX_WORKDIR,
        prompt,
    ]
    return subprocess.run(
        cmd,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=1800,
    ).stdout


def download_file(file_id, suffix):
    info = api("getFile", {"file_id": file_id})
    path = info["result"]["file_path"]
    url = f"https://api.telegram.org/file/bot{TOKEN}/{path}"
    fd, local = tempfile.mkstemp(suffix=suffix)
    os.close(fd)
    urllib.request.urlretrieve(url, local)
    return local


def transcribe(path):
    boundary = "----codexbridge"
    with open(path, "rb") as f:
        content = f.read()
    filename = os.path.basename(path)
    body = (
        f"--{boundary}\r\n"
        f'Content-Disposition: form-data; name="file"; filename="{filename}"\r\n'
        "Content-Type: application/octet-stream\r\n\r\n"
    ).encode() + content + f"\r\n--{boundary}--\r\n".encode()
    req = urllib.request.Request(
        TRANSCRIBE_URL,
        data=body,
        headers={"Content-Type": f"multipart/form-data; boundary={boundary}"},
    )
    with urllib.request.urlopen(req, timeout=180) as resp:
        data = json.loads(resp.read().decode())
    return data.get("text", "")


def audio_message(message):
    if "voice" in message:
        return message["voice"]["file_id"], ".ogg"
    if "audio" in message:
        name = message["audio"].get("file_name") or "audio.ogg"
        suffix = os.path.splitext(name)[1] or ".ogg"
        if suffix in (".oga", ".opus"):
            suffix = ".ogg"
        return message["audio"]["file_id"], suffix
    doc = message.get("document")
    if doc and (doc.get("mime_type", "").startswith("audio/") or os.path.splitext(doc.get("file_name", ""))[1] in (".oga", ".opus", ".ogg", ".mp3", ".wav", ".m4a")):
        suffix = os.path.splitext(doc.get("file_name", ""))[1] or ".ogg"
        if suffix in (".oga", ".opus"):
            suffix = ".ogg"
        return doc["file_id"], suffix
    return None


def handle(message):
    chat_id = message["chat"]["id"]
    if not allowed(chat_id):
        if message.get("text", "").strip() == "/getid":
            send(chat_id, f"<code>{chat_id}</code>")
        return

    text = message.get("text", "").strip()
    if text == "/getid":
        send(chat_id, f"<code>{chat_id}</code>")
        return
    if text == "/status":
        out = run_shell("codex --version && codex login status && codex app-server daemon version")
        send(chat_id, f"<pre>{html.escape(out)}</pre>")
        return
    if text.startswith("/run "):
        out = run_shell(text[5:])
        send(chat_id, f"<pre>{html.escape(out)}</pre>")
        return

    audio = audio_message(message)
    if audio:
        file_id, suffix = audio
        try:
            path = download_file(file_id, suffix)
            text = transcribe(path)
            send(chat_id, "<b>Transcript</b>\n" + html.escape(text))
        except Exception as exc:
            send(chat_id, "<b>Audio transcription failed</b>\n" + html.escape(str(exc)))
            return
        finally:
            try:
                os.unlink(path)
            except Exception:
                pass

    if not text:
        return
    send(chat_id, "<b>Codex is working...</b>")
    out = run_codex(text)
    send(chat_id, f"<pre>{html.escape(out)}</pre>")


def main():
    offset = 0
    while True:
        try:
            updates = api("getUpdates", {
                "timeout": 50,
                "offset": offset,
                "allowed_updates": json.dumps(["message", "callback_query"]),
            })
            for update in updates.get("result", []):
                offset = update["update_id"] + 1
                if "message" in update:
                    handle(update["message"])
        except Exception as exc:
            print(f"telegram bridge error: {exc}", flush=True)
            time.sleep(5)


if __name__ == "__main__":
    main()

