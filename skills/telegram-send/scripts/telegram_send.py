#!/usr/bin/env python3
from __future__ import annotations

import argparse
import asyncio
import json
import os
import re
import sys
import urllib.parse
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Any


DEFAULT_MAC_GIT_ROOT = Path("/Users/a.putinkt-team.de/Library/Mobile Documents/com~apple~CloudDocs/GIT")


@dataclass(frozen=True)
class Recipient:
    query: str
    destination: str
    label: str
    source: str


def _norm(value: str) -> str:
    value = value.casefold().replace("@", " ")
    value = re.sub(r"[^0-9a-zа-яё]+", " ", value)
    return " ".join(value.split())


def _russian_name_forms(value: str) -> set[str]:
    """Return conservative grammatical forms for one Russian name token."""
    value = _norm(value)
    if not value or " " in value or not re.fullmatch(r"[а-яё]+", value):
        return {value}
    forms = {value}
    if value.endswith("ий") and len(value) > 4:
        stem = value[:-2]
        forms.update(stem + ending for ending in ("его", "ему", "им", "ем"))
    elif value.endswith("ый") and len(value) > 4:
        stem = value[:-2]
        forms.update(stem + ending for ending in ("ого", "ому", "ым", "ом"))
    elif value.endswith("ей") and len(value) > 4:
        stem = value[:-1]
        forms.update(stem + ending for ending in ("я", "ю", "ем", "е"))
    elif value.endswith("й") and len(value) > 3:
        stem = value[:-1]
        forms.update(stem + ending for ending in ("я", "ю", "ем", "е"))
    elif value.endswith("а") and len(value) > 3:
        stem = value[:-1]
        forms.update(stem + ending for ending in ("ы", "и", "е", "у", "ой", "ою"))
    elif value.endswith("я") and len(value) > 3:
        stem = value[:-1]
        forms.update(stem + ending for ending in ("и", "е", "ю", "ей", "ею"))
    elif value.endswith("ь") and len(value) > 3:
        stem = value[:-1]
        forms.update(stem + ending for ending in ("я", "ю", "ем", "е", "и", "ью"))
    elif value[-1] not in "аеёиоуыэюя":
        forms.update(value + ending for ending in ("а", "у", "ом", "е", "ым", "им"))
    return forms


def _token_matches(query_token: str, alias_token: str) -> bool:
    return query_token == alias_token or query_token in _russian_name_forms(alias_token)


def _alias_matches(query: str, alias: str) -> bool:
    query_tokens = _norm(query).split()
    alias_tokens = _norm(alias).split()
    if not query_tokens or not alias_tokens:
        return False
    return all(any(_token_matches(query_token, alias_token) for query_token in query_tokens) for alias_token in alias_tokens)


def _repo_root() -> Path:
    configured = os.getenv("GIT_ROOT", "").strip()
    if configured:
        return Path(configured).expanduser().resolve()
    cwd = Path.cwd().resolve()
    for path in [cwd, *cwd.parents]:
        if (path / "README.md").exists() and _telegram_chats_root(path).exists():
            return path
    if (Path.home() / "GIT").exists():
        return Path.home() / "GIT"
    return DEFAULT_MAC_GIT_ROOT


def _telegram_chats_root(root: Path) -> Path:
    return root / "assistants" / "telegram-chats"


def _load_env_file(path: Path) -> None:
    if not path.exists():
        return
    for raw in path.read_text(encoding="utf-8", errors="ignore").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        if key and key not in os.environ:
            os.environ[key] = value


def load_env(root: Path) -> None:
    for path in (
        root / ".env-telegram",
        root / "assistants" / ".env",
        root / "assistants" / "relationship-warmer" / ".env",
    ):
        _load_env_file(path)


def _extract_telegram_destination(text: str) -> str:
    username_match = re.search(r"@[-_0-9A-Za-z]{3,}", text)
    if username_match:
        return username_match.group(0)
    phone_match = re.search(r"\*\*Телефон\*\*:\s*([+()0-9 \t-]{7,})", text)
    if phone_match:
        phone = re.sub(r"[^+0-9]", "", phone_match.group(1))
        if phone:
            return phone
    peer_match = re.search(r"peer id [`']?(-?\d+)[`']?", text, re.IGNORECASE)
    if peer_match:
        return peer_match.group(1)
    chat_id_match = re.search(r"chat[_ -]?id [`']?(-?\d+)[`']?", text, re.IGNORECASE)
    if chat_id_match:
        return chat_id_match.group(1)
    tg_line = re.search(r"\*\*Telegram\*\*:\s*(.+)", text)
    if tg_line:
        inline = tg_line.group(1)
        quoted = re.findall(r"`([^`]+)`", inline)
        for value in quoted:
            if value.startswith("@") or re.fullmatch(r"-?\d+", value):
                return value
    return ""


def _recipient_from_people(root: Path, query: str) -> list[Recipient]:
    people_dir = root / "peoples"
    if not people_dir.exists():
        return []
    matches: list[Recipient] = []
    for path in people_dir.glob("*.md"):
        text = path.read_text(encoding="utf-8", errors="ignore")
        title_match = re.search(r"^#\s+(.+)$", text, re.MULTILINE)
        title = title_match.group(1).strip() if title_match else path.stem
        aliases = {path.stem, title, *title.split()}
        if not any(_alias_matches(query, alias) for alias in aliases if alias):
            continue
        destination = _extract_telegram_destination(text)
        if destination:
            matches.append(Recipient(query=query, destination=destination, label=title, source=str(path.relative_to(root))))
    return matches


def _recipient_from_contacts(query: str) -> list[Recipient]:
    contacts_path = Path(__file__).resolve().parent.parent / "contacts.json"
    if not contacts_path.exists():
        return []
    try:
        contacts = json.loads(contacts_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return []
    matches: list[Recipient] = []
    for contact in contacts:
        label = str(contact.get("name") or "").strip()
        destination = str(contact.get("telegram") or "").strip()
        aliases = [label, destination, *(contact.get("aliases") or [])]
        if label and destination and any(_alias_matches(query, str(alias)) for alias in aliases if alias):
            matches.append(Recipient(query=query, destination=destination, label=label, source=str(contacts_path)))
    return matches


def _recipient_from_state(root: Path, query: str) -> list[Recipient]:
    state_path = _telegram_chats_root(root) / "state.json"
    if not state_path.exists():
        return []
    try:
        state = json.loads(state_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return []
    matches: list[Recipient] = []
    for label, data in (state.get("chats") or {}).items():
        destination = str((data or {}).get("chat_id") or "")
        if not destination:
            continue
        if _alias_matches(query, label) or query == destination:
            matches.append(Recipient(query=query, destination=destination, label=label, source=str(state_path.relative_to(root))))
    return matches


def resolve_recipient(root: Path, query: str) -> Recipient:
    query = query.strip()
    if not query:
        raise RuntimeError("recipient is required")
    if query.startswith("@") or query.startswith("+") or re.fullmatch(r"-?\d+", query):
        return Recipient(query=query, destination=query, label=query, source="explicit")
    matches = _recipient_from_people(root, query) + _recipient_from_contacts(query) + _recipient_from_state(root, query)
    unique: dict[tuple[str, str], Recipient] = {(item.destination, item.label): item for item in matches}
    matches = list(unique.values())
    if not matches:
        raise RuntimeError(f"recipient not found: {query}")
    destinations = {item.destination for item in matches}
    if len(destinations) > 1:
        details = "; ".join(f"{item.label} -> {item.destination} ({item.source})" for item in matches)
        raise RuntimeError(f"ambiguous recipient: {query}: {details}")
    return matches[0]


def message_from_args(args: argparse.Namespace) -> str:
    sources = [bool(args.message), bool(args.message_file), bool(args.stdin)]
    if sum(sources) != 1:
        raise RuntimeError("provide exactly one of --message, --message-file, or --stdin")
    if args.message:
        return args.message
    if args.stdin:
        return sys.stdin.read()
    return Path(args.message_file).read_text(encoding="utf-8")


def _bot_parse_mode(value: str) -> str:
    mapping = {
        "none": "",
        "html": "HTML",
        "md": "Markdown",
        "markdown": "Markdown",
        "markdownv2": "MarkdownV2",
    }
    return mapping[value]


def _user_parse_mode(value: str) -> str | None:
    mapping = {
        "none": None,
        "html": "html",
        "md": "md",
        "markdown": "md",
        "markdownv2": "md",
    }
    return mapping[value]


async def send_user_api(destination: str, text: str, parse_mode: str, reply_to: int | None = None, file: str | None = None) -> dict[str, Any]:
    try:
        from telethon import TelegramClient
        from telethon.sessions import StringSession
        from telethon.tl.types import PeerChannel
    except ImportError as exc:
        raise RuntimeError("telethon is required for userapi sending; run inside relationship-warmer .venv or install telethon") from exc

    api_id = os.getenv("TELEGRAM_API_ID") or os.getenv("TELEGRAM_USER_APP_API_ID") or ""
    api_hash = os.getenv("TELEGRAM_API_HASH") or os.getenv("TELEGRAM_USER_APP_API_HASH") or ""
    if not api_id or not api_hash:
        raise RuntimeError("TELEGRAM_API_ID and TELEGRAM_API_HASH are required")

    session_string = os.getenv("TELEGRAM_USER_SESSION", "").strip()
    if session_string:
        session: Any = StringSession(session_string)
    else:
        session_file = os.getenv("TELEGRAM_USER_SESSION_FILE", "").strip()
        if not session_file:
            root = _repo_root()
            session_file = str(root / "assistants" / "relationship-warmer" / "state" / "telegram-user.session")
        path = Path(session_file).expanduser()
        if not path.is_absolute():
            path = _repo_root() / "assistants" / "relationship-warmer" / path
        if path.suffix == ".session":
            path = path.with_suffix("")
        if not path.exists() and not path.with_suffix(".session").exists():
            raise RuntimeError("TELEGRAM_USER_SESSION_FILE must point to an authorized Telethon session or TELEGRAM_USER_SESSION must be set")
        session = str(path)

    client = TelegramClient(session, int(api_id), api_hash, connection_retries=2, request_retries=2, timeout=10)
    async with client:
        if not await client.is_user_authorized():
            raise RuntimeError("Telegram user session is not authorized")
        entity: Any = destination
        if reply_to is not None and re.fullmatch(r"-?\d+", destination):
            marked_id = int(destination)
            if marked_id < -1000000000000:
                entity = PeerChannel(int(str(abs(marked_id))[3:]))
            elif marked_id > 1000000000:
                entity = PeerChannel(marked_id)
        if file:
            # ponytail: file only via userapi; caption limit is Telegram's 1024
            message = await client.send_file(
                entity,
                file,
                caption=text[:1024],
                parse_mode=_user_parse_mode(parse_mode),
                reply_to=reply_to,
            )
        else:
            message = await client.send_message(
                entity,
                text[:3900],
                parse_mode=_user_parse_mode(parse_mode),
                reply_to=reply_to,
            )
    return {"provider": "telegram_user_api", "destination": destination, "telegram_message_id": int(message.id)}


def send_bot_api(destination: str, text: str, parse_mode: str, timeout: int, reply_to: int | None = None) -> dict[str, Any]:
    token = os.getenv("TELEGRAM_BOT_TOKEN", "").strip()
    if not token:
        raise RuntimeError("TELEGRAM_BOT_TOKEN is required for bot sending")
    data = {
        "chat_id": destination,
        "text": text[:3900],
        "disable_web_page_preview": "true",
    }
    mode = _bot_parse_mode(parse_mode)
    if mode:
        data["parse_mode"] = mode
    if reply_to is not None:
        data["message_thread_id"] = str(reply_to)
    body = urllib.parse.urlencode(data).encode()
    req = urllib.request.Request(
        f"https://api.telegram.org/bot{token}/sendMessage",
        data=body,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        payload = json.loads(resp.read().decode())
    if not payload.get("ok"):
        raise RuntimeError("telegram bot api failed: sendMessage")
    result = payload.get("result") or {}
    return {"provider": "telegram_bot_api", "destination": destination, "telegram_message_id": result.get("message_id")}


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Send a Telegram message from Andrey's userapi session or a bot.")
    parser.add_argument("--to", required=True, help="Recipient name, peoples/*.md profile name, @username, or numeric peer/chat id")
    parser.add_argument("--message", help="Message text")
    parser.add_argument("--message-file", help="UTF-8 file with message text")
    parser.add_argument("--stdin", action="store_true", help="Read message text from stdin")
    parser.add_argument("--file", help="Attach a document (userapi only); message text becomes the caption")
    parser.add_argument("--sender", choices=["user", "bot"], default="user", help="Sender identity. Default: userapi first-person")
    parser.add_argument("--parse-mode", choices=["none", "html", "md", "markdown", "markdownv2"], default="none")
    parser.add_argument("--reply-to", type=int, help="Reply/topic root message id for forum topics")
    parser.add_argument("--timeout", type=int, default=60, help="Network timeout in seconds for actual sending")
    parser.add_argument("--dry-run", action="store_true", help="Resolve and print payload without sending")
    parser.add_argument("--yes", action="store_true", help="Required for actual sending")
    parser.add_argument("--json", action="store_true", help="Print machine-readable JSON")
    return parser


def main() -> int:
    args = build_parser().parse_args()
    root = _repo_root()
    load_env(root)
    try:
        recipient = resolve_recipient(root, args.to)
        text = message_from_args(args).strip()
        if not text:
            raise RuntimeError("message text is empty")
        if args.file:
            if args.sender != "user":
                raise RuntimeError("--file is supported only with --sender user")
            if not Path(args.file).is_file():
                raise RuntimeError(f"attachment not found: {args.file}")
        payload = {
            "status": "dry_run" if args.dry_run else "ready",
            "sender": args.sender,
            "recipient": {
                "query": recipient.query,
                "label": recipient.label,
                "destination": recipient.destination,
                "source": recipient.source,
            },
            "parse_mode": args.parse_mode,
            "reply_to": args.reply_to,
            "file": args.file,
            "text": text,
        }
        if args.dry_run:
            print(json.dumps(payload, ensure_ascii=False, indent=2) if args.json else _human(payload))
            return 0
        if not args.yes:
            raise RuntimeError("actual sending requires --yes; use --dry-run to preview")
        if args.sender == "user":
            try:
                result = asyncio.run(
                    asyncio.wait_for(
                        send_user_api(recipient.destination, text, args.parse_mode, reply_to=args.reply_to, file=args.file),
                        timeout=args.timeout,
                    )
                )
            except TimeoutError as exc:
                raise RuntimeError(f"userapi send timed out after {args.timeout}s") from exc
            except asyncio.TimeoutError as exc:
                raise RuntimeError(f"userapi send timed out after {args.timeout}s") from exc
        else:
            result = send_bot_api(recipient.destination, text, args.parse_mode, args.timeout, reply_to=args.reply_to)
        payload.update({"status": "sent", "result": result})
        print(json.dumps(payload, ensure_ascii=False, indent=2) if args.json else _human(payload))
        return 0
    except Exception as exc:
        error = str(exc) or exc.__class__.__name__
        if args.json:
            print(json.dumps({"status": "error", "error": error}, ensure_ascii=False), file=sys.stderr)
        else:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1


def _human(payload: dict[str, Any]) -> str:
    recipient = payload["recipient"]
    lines = [
        f"status: {payload['status']}",
        f"sender: {payload['sender']}",
        f"to: {recipient['label']} -> {recipient['destination']} ({recipient['source']})",
        f"parse_mode: {payload['parse_mode']}",
        f"reply_to: {payload.get('reply_to') or '-'}",
        "text:",
        payload["text"],
    ]
    result = payload.get("result")
    if result:
        lines.insert(3, f"message_id: {result.get('telegram_message_id')}")
    return "\n".join(lines)


if __name__ == "__main__":
    raise SystemExit(main())
