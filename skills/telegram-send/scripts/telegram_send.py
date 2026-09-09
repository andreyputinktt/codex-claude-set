#!/usr/bin/env python3
from __future__ import annotations

import argparse
import asyncio
import json
import os
import re
import sqlite3
import sys
import urllib.parse
import urllib.request
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


DEFAULT_MAC_GIT_ROOT = Path("/Users/a.putinkt-team.de/Library/Mobile Documents/com~apple~CloudDocs/GIT")


@dataclass(frozen=True)
class Recipient:
    query: str
    destination: str
    label: str
    source: str


@dataclass(frozen=True)
class TelegramEntity:
    type: str
    offset: int
    length: int
    url: str = ""

    def as_bot_api(self) -> dict[str, Any]:
        result: dict[str, Any] = {
            "type": self.type,
            "offset": self.offset,
            "length": self.length,
        }
        if self.url:
            result["url"] = self.url
        return result


@dataclass(frozen=True)
class PreparedMessage:
    text: str
    entities: tuple[TelegramEntity, ...] = ()


_TRANSLIT = {
    "а": "a", "б": "b", "в": "v", "г": "g", "д": "d", "е": "e", "ё": "e", "ж": "zh",
    "з": "z", "и": "i", "й": "i", "к": "k", "л": "l", "м": "m", "н": "n", "о": "o",
    "п": "p", "р": "r", "с": "s", "т": "t", "у": "u", "ф": "f", "х": "h", "ц": "c",
    "ч": "ch", "ш": "sh", "щ": "sch", "ъ": "", "ы": "y", "ь": "", "э": "e",
    "ю": "yu", "я": "ya",
}


def _norm(value: str) -> str:
    """Lowercase, split glued names (`LadaIkonnikova`) and drop punctuation."""
    value = re.sub(r"(?<=[a-zа-яё])(?=[A-ZА-ЯЁ])", " ", value)
    value = value.casefold().replace("@", " ")
    value = re.sub(r"[^0-9a-zа-яё]+", " ", value)
    return " ".join(value.split())


def _fold(token: str) -> str:
    """One comparable form for a token: Cyrillic transliterated to Latin."""
    return "".join(_TRANSLIT.get(char, char) for char in token)


def _token_matches(query_token: str, alias_token: str) -> bool:
    """Same name up to a grammatical ending or a transliteration.

    Russian inflects the ending and leaves the stem alone, and the same person
    is written both in Cyrillic and in Latin, so «Тимофееву», «Тимофеев» and
    `Timofeev` all fold to one stem here. Numbers must match exactly: an id or a
    phone is never a near miss.

    ponytail: stem comparison instead of an ending table. It costs three lines,
    covers every case at once, and over-matching surfaces as an
    `ambiguous recipient` error rather than as a message to the wrong person.
    """
    left, right = _fold(query_token), _fold(alias_token)
    if left == right:
        return True
    if left.isdigit() or right.isdigit():
        return False
    common = len(os.path.commonprefix([left, right]))
    return common >= 3 and len(left) - common <= 2 and len(right) - common <= 2


def _alias_matches(query: str, alias: str) -> bool:
    """True when every token of the query is present in the alias.

    Subset, not equality: «Тимофееву» has to find «Алексей Тимофеев» and
    `LadaIkonnikova`, while «Александр» must not match «Алексей».
    """
    query_tokens = _norm(query).split()
    alias_tokens = _norm(alias).split()
    if not query_tokens or not alias_tokens:
        return False
    return all(
        any(_token_matches(query_token, alias_token) for alias_token in alias_tokens)
        for query_token in query_tokens
    )


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


def _dialog_cache_path() -> Path:
    """Runtime cache, outside the repo: it holds real contact names."""
    configured = os.getenv("TELEGRAM_DIALOG_CACHE", "").strip()
    if configured:
        return Path(configured).expanduser()
    base = os.getenv("XDG_CACHE_HOME", "").strip() or str(Path.home() / ".cache")
    return Path(base).expanduser() / "telegram-send" / "dialogs.json"


def _telethon_session() -> Any:
    from telethon.sessions import StringSession

    session_string = os.getenv("TELEGRAM_USER_SESSION", "").strip()
    if session_string:
        return StringSession(session_string)
    path = _user_session_file()
    if path is None:
        raise RuntimeError("no authorized Telethon session for dialog lookup")
    return str(path.with_suffix(""))


def _fetch_dialogs(limit: int = 500) -> list[dict[str, Any]]:
    """One MTProto dialog scan. Names come from Telegram, so treat them as data."""
    from telethon import TelegramClient
    from telethon.tl.types import User

    api_id = os.getenv("TELEGRAM_API_ID") or os.getenv("TELEGRAM_USER_APP_API_ID") or ""
    api_hash = os.getenv("TELEGRAM_API_HASH") or os.getenv("TELEGRAM_USER_APP_API_HASH") or ""
    if not api_id or not api_hash:
        raise RuntimeError("TELEGRAM_API_ID and TELEGRAM_API_HASH are required for dialog lookup")

    async def run() -> list[dict[str, Any]]:
        client = TelegramClient(_telethon_session(), int(api_id), api_hash, connection_retries=2, request_retries=2, timeout=15)
        rows: list[dict[str, Any]] = []
        async with client:
            if not await client.is_user_authorized():
                raise RuntimeError("Telegram user session is not authorized")
            async for dialog in client.iter_dialogs(limit=limit):
                entity = dialog.entity
                is_user = isinstance(entity, User) and not getattr(entity, "bot", False)
                name = " ".join(
                    part for part in [getattr(entity, "first_name", "") or "", getattr(entity, "last_name", "") or ""] if part
                ).strip() or (dialog.name or "")
                rows.append(
                    {
                        "id": int(dialog.id),
                        "name": name,
                        "username": ("@" + entity.username) if getattr(entity, "username", None) else "",
                        "is_user": bool(is_user),
                        "last": dialog.date.isoformat() if dialog.date else "",
                    }
                )
        return rows

    return asyncio.run(run())


def _load_dialogs(max_age_hours: float = 168.0, refresh: bool = False) -> list[dict[str, Any]]:
    cache = _dialog_cache_path()
    if not refresh and cache.exists():
        try:
            payload = json.loads(cache.read_text(encoding="utf-8"))
            saved = datetime.fromisoformat(payload.get("saved_at", ""))
            if (datetime.now(timezone.utc) - saved).total_seconds() <= max_age_hours * 3600:
                return payload.get("dialogs") or []
        except Exception:
            pass
    rows = _fetch_dialogs()
    cache.parent.mkdir(parents=True, exist_ok=True)
    cache.write_text(
        json.dumps({"saved_at": datetime.now(timezone.utc).isoformat(), "dialogs": rows}, ensure_ascii=False, indent=1),
        encoding="utf-8",
    )
    return rows


def _recipient_from_dialogs(query: str) -> list[Recipient]:
    """Personal chats first: a human name must not resolve to a group."""
    try:
        dialogs = _load_dialogs()
    except Exception as exc:  # no session, no network, no telethon
        if os.getenv("TELEGRAM_DEBUG"):
            print(f"dialog lookup skipped: {exc}", file=sys.stderr)
        return []
    hits: list[Recipient] = []
    for row in dialogs:
        if not row.get("is_user"):
            continue
        aliases = [row.get("name", ""), row.get("username", "")]
        if not any(_alias_matches(query, alias) for alias in aliases if alias):
            continue
        destination = row.get("username") or str(row.get("id"))
        hits.append(Recipient(query=query, destination=destination, label=row.get("name") or destination, source="telegram dialogs"))
    if hits:
        return hits
    for row in dialogs:  # groups only when nothing personal matched
        if row.get("is_user"):
            continue
        if _alias_matches(query, row.get("name", "")):
            hits.append(Recipient(query=query, destination=str(row.get("id")), label=row.get("name", ""), source="telegram dialogs (group)"))
    return hits


def _destination_rank(recipient: Recipient) -> int:
    """`@username` first, then a phone, then a bare id.

    A username resolves with ResolveUsername; a bare id needs the session cache
    and, when it misses, a contacts scan Telegram answers with a FloodWait.
    """
    if recipient.destination.startswith("@"):
        return 0
    if recipient.destination.startswith("+"):
        return 1
    return 2


def _collapse_same_person(matches: list[Recipient]) -> list[Recipient]:
    """One person listed by several sources is one candidate, not an ambiguity.

    A contact card, `state.json` and the dialog scan hold the same human under
    `@KopkinAnton`, `KopkinAnton` and a numeric id; only genuinely different
    names should reach the ambiguity error.
    """
    kept: list[Recipient] = []
    for item in sorted(matches, key=_destination_rank):
        same = any(
            _alias_matches(item.label, other.label) or _alias_matches(other.label, item.label)
            for other in kept
        )
        if not same:
            kept.append(item)
    return kept


def resolve_recipient(root: Path, query: str) -> Recipient:
    query = query.strip()
    if not query:
        raise RuntimeError("recipient is required")
    if query.startswith("@") or query.startswith("+") or re.fullmatch(r"-?\d+", query):
        return Recipient(query=query, destination=query, label=query, source="explicit")
    matches = _recipient_from_people(root, query) + _recipient_from_contacts(query) + _recipient_from_state(root, query)
    if not matches:
        matches = _recipient_from_dialogs(query)
    unique: dict[tuple[str, str], Recipient] = {(item.destination, item.label): item for item in matches}
    matches = _collapse_same_person(list(unique.values()))
    if not matches:
        raise RuntimeError(f"recipient not found: {query}")
    destinations = {item.destination for item in matches}
    if len(destinations) > 1:
        shown = matches[:8]
        details = "; ".join(f"{item.label} -> {item.destination} ({item.source})" for item in shown)
        if len(matches) > len(shown):
            details += f"; ... {len(matches) - len(shown)} more"
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
        "plain": "",
        "html": "HTML",
        "markdown": "Markdown",
        "markdownv2": "MarkdownV2",
    }
    return mapping[value]


def _user_parse_mode(value: str) -> str | None:
    mapping = {
        "plain": None,
        "html": "html",
        "markdown": "md",
        "markdownv2": "md",
    }
    return mapping[value]


def _utf16_length(value: str) -> int:
    return len(value.encode("utf-16-le")) // 2


_TELEGRAM_MARKUP = re.compile(
    r"\*\*(?P<bold>[^*\n]+)\*\*"
    r"|\*(?P<italic>[^*\n]+)\*"
    r"|`(?P<code>[^`\n]+)`"
    r"|\[(?P<link_text>[^\]\n]+)\]\((?P<link_url>https?://[^)\s]+)\)"
)


_AUTO_URL = re.compile(r"https?://[^\s<>()]+")
_AUTO_BULLET_LABEL = re.compile(
    r"(?m)^[ \t]*(?:[•▪◦‣]|[-–—]|\d+[.)])\s+(?P<label>[^:\n]{1,80}):"
)


def _normalize_telegram_source(source: str) -> str:
    """Make common serialized line breaks readable in Telegram's default format."""
    source = source.replace("\r\n", "\n").replace("\r", "\n")
    return (
        source.replace("\\r\\n", "\n")
        .replace("\\n", "\n")
        .replace("\\r", "\n")
        .replace("\\t", "\t")
    )


def _entity_for_chars(text: str, entity_type: str, start: int, end: int, url: str = "") -> TelegramEntity:
    return TelegramEntity(entity_type, _utf16_length(text[:start]), _utf16_length(text[start:end]), url)


def _entities_overlap(left: TelegramEntity, right: TelegramEntity) -> bool:
    return left.offset < right.offset + right.length and right.offset < left.offset + left.length


def _with_automatic_entities(text: str, explicit_entities: tuple[TelegramEntity, ...]) -> tuple[TelegramEntity, ...]:
    """Add restrained structure without overriding explicit source formatting."""
    entities = list(explicit_entities)

    def add(entity: TelegramEntity) -> None:
        if entity.length and not any(_entities_overlap(entity, existing) for existing in entities):
            entities.append(entity)

    heading = re.match(r"^[ \t]*(?P<heading>\S[^\n]*?)[ \t]*\n[ \t]*\n", text)
    if heading:
        start, end = heading.span("heading")
        add(_entity_for_chars(text, "bold", start, end))

    for match in _AUTO_BULLET_LABEL.finditer(text):
        start, end = match.span("label")
        add(_entity_for_chars(text, "bold", start, end))

    for match in _AUTO_URL.finditer(text):
        url = match.group(0).rstrip(".,;:!?")
        if url:
            add(_entity_for_chars(text, "url", match.start(), match.start() + len(url)))

    return tuple(sorted(entities, key=lambda entity: (entity.offset, entity.length)))

def prepare_telegram_message(source: str, limit: int = 3900) -> PreparedMessage:
    """Convert predictable lightweight markup to Telegram-native entities."""
    source = _normalize_telegram_source(source)
    parts: list[str] = []
    entities: list[TelegramEntity] = []
    cursor = 0
    output_utf16_offset = 0
    for match in _TELEGRAM_MARKUP.finditer(source):
        prefix = source[cursor : match.start()]
        parts.append(prefix)
        output_utf16_offset += _utf16_length(prefix)

        if match.group("bold") is not None:
            entity_type, value, url = "bold", match.group("bold"), ""
        elif match.group("italic") is not None:
            entity_type, value, url = "italic", match.group("italic"), ""
        elif match.group("code") is not None:
            entity_type, value, url = "code", match.group("code"), ""
        else:
            entity_type = "text_link"
            value = match.group("link_text")
            url = match.group("link_url")

        parts.append(value)
        length = _utf16_length(value)
        entities.append(TelegramEntity(entity_type, output_utf16_offset, length, url))
        output_utf16_offset += length
        cursor = match.end()

    parts.append(source[cursor:])
    text = "".join(parts)[:limit]
    available_utf16 = _utf16_length(text)
    safe_entities = tuple(
        entity for entity in entities if entity.offset + entity.length <= available_utf16
    )
    return PreparedMessage(text=text, entities=_with_automatic_entities(text, safe_entities))


def prepare_message(source: str, message_format: str, limit: int) -> PreparedMessage:
    if message_format == "telegram":
        return prepare_telegram_message(source, limit)
    return PreparedMessage(text=source[:limit])


def resolve_message_format(format_value: str | None, legacy_parse_mode: str | None) -> str:
    if format_value and legacy_parse_mode:
        raise RuntimeError("use either --format or legacy --parse-mode, not both")
    if format_value:
        return format_value
    if legacy_parse_mode:
        return {
            "none": "plain",
            "html": "html",
            "md": "markdown",
            "markdown": "markdown",
            "markdownv2": "markdownv2",
        }[legacy_parse_mode]
    return "telegram"


def _telethon_entities(entities: tuple[TelegramEntity, ...]) -> list[Any]:
    from telethon.tl.types import (
        MessageEntityBold,
        MessageEntityCode,
        MessageEntityItalic,
        MessageEntityTextUrl,
        MessageEntityUrl,
    )

    result: list[Any] = []
    for entity in entities:
        if entity.type == "bold":
            result.append(MessageEntityBold(entity.offset, entity.length))
        elif entity.type == "italic":
            result.append(MessageEntityItalic(entity.offset, entity.length))
        elif entity.type == "code":
            result.append(MessageEntityCode(entity.offset, entity.length))
        elif entity.type == "text_link":
            result.append(MessageEntityTextUrl(entity.offset, entity.length, entity.url))
        elif entity.type == "url":
            result.append(MessageEntityUrl(entity.offset, entity.length))
    return result


def needs_cache_lookup(destination: str) -> bool:
    """True when Telegram would resolve this destination via a contacts scan.

    Bare numeric ids and phone numbers do. Usernames do not: they resolve with
    ResolveUsername, which is not rate-limited the same way.
    """
    return bool(re.fullmatch(r"-?\d+", destination)) or destination.startswith("+")


def cached_peer(session: Any, destination: str, peer_channel: Any, peer_chat: Any) -> Any:
    """Peer for a numeric id or a phone number.

    Negative ids are groups or channels and need no lookup. Everything else is
    read from the local session cache.

    ponytail: never hand these to Telethon as a string. Telethon then treats the
    value as a username/phone query and falls back to a full contacts scan,
    which Telegram rate-limits with a FloodWait measured in hours.
    """
    if re.fullmatch(r"-?\d+", destination):
        value = int(destination)
        if value < 0:
            marked = str(-value)
            if marked.startswith("100"):
                return peer_channel(int(marked[3:]))
            return peer_chat(-value)
        key: Any = value
    else:
        key = destination
    try:
        return session.get_input_entity(key)
    except ValueError as exc:
        raise RuntimeError(
            f"{destination} is not in this session's entity cache, so resolving it "
            "would need a rate-limited contacts lookup; pass --access-hash, "
            "use @username, or send with --sender bot"
        ) from exc


def _user_session_file() -> Path | None:
    """Path to the Telethon SQLite session, or None when it cannot be located."""
    if os.getenv("TELEGRAM_USER_SESSION", "").strip():
        return None
    session_file = os.getenv("TELEGRAM_USER_SESSION_FILE", "").strip()
    if not session_file:
        session_file = str(_repo_root() / "assistants" / "relationship-warmer" / "state" / "telegram-user.session")
    path = Path(session_file).expanduser()
    if not path.is_absolute():
        path = _repo_root() / "assistants" / "relationship-warmer" / path
    if path.suffix == ".session":
        path = path.with_suffix("")
    for candidate in (path.with_suffix(".session"), path):
        if candidate.exists():
            return candidate
    return None


def peer_cache_note(destination: str) -> str:
    """Offline verdict on whether a destination can be resolved without network.

    Read-only SQLite on the session file, so --dry-run tells the truth about
    numeric ids and phones instead of only echoing them back.
    """
    if not needs_cache_lookup(destination):
        return ""
    if re.fullmatch(r"-\d+", destination):
        return "group or channel id, no lookup needed"
    path = _user_session_file()
    if path is None:
        return "session cache not checked"
    try:
        connection = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
        try:
            if destination.startswith("+"):
                row = connection.execute(
                    "select 1 from entities where phone = ?", (destination.lstrip("+"),)
                ).fetchone()
            else:
                row = connection.execute(
                    "select 1 from entities where id = ?", (int(destination),)
                ).fetchone()
        finally:
            connection.close()
    except (sqlite3.Error, OSError, ValueError):
        return "session cache not checked"
    if row:
        return "in session cache"
    return "NOT in session cache - send will fail; use @username or --sender bot"


async def send_user_api(
    destination: str,
    prepared: PreparedMessage,
    message_format: str,
    reply_to: int | None = None,
    file: str | None = None,
    access_hash: str = "",
) -> dict[str, Any]:
    try:
        from telethon import TelegramClient
        from telethon.sessions import StringSession
        from telethon.tl.types import InputPeerUser, PeerChannel, PeerChat
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
        path = _user_session_file()
        if path is None:
            raise RuntimeError("TELEGRAM_USER_SESSION_FILE must point to an authorized Telethon session or TELEGRAM_USER_SESSION must be set")
        session = str(path.with_suffix(""))

    client = TelegramClient(session, int(api_id), api_hash, connection_retries=2, request_retries=2, timeout=10)
    async with client:
        if not await client.is_user_authorized():
            raise RuntimeError("Telegram user session is not authorized")
        entity: Any = destination
        if re.fullmatch(r"\d+", destination) and re.fullmatch(r"-?\d+", access_hash):
            entity = InputPeerUser(int(destination), int(access_hash))
        elif needs_cache_lookup(destination):
            entity = cached_peer(client.session, destination, PeerChannel, PeerChat)
        if reply_to is not None and re.fullmatch(r"-?\d+", destination):
            marked_id = int(destination)
            if marked_id < -1000000000000:
                entity = PeerChannel(int(str(abs(marked_id))[3:]))
            elif marked_id > 1000000000:
                entity = PeerChannel(marked_id)
        if file:
            # ponytail: file only via userapi; caption limit is Telegram's 1024
            kwargs: dict[str, Any] = {
                "caption": prepared.text,
                "reply_to": reply_to,
            }
            if message_format == "telegram":
                kwargs["formatting_entities"] = _telethon_entities(prepared.entities)
                kwargs["parse_mode"] = None
            else:
                kwargs["parse_mode"] = _user_parse_mode(message_format)
            message = await client.send_file(entity, file, **kwargs)
        else:
            kwargs = {"reply_to": reply_to}
            if message_format == "telegram":
                kwargs["formatting_entities"] = _telethon_entities(prepared.entities)
                kwargs["parse_mode"] = None
            else:
                kwargs["parse_mode"] = _user_parse_mode(message_format)
            message = await client.send_message(entity, prepared.text, **kwargs)
    return {"provider": "telegram_user_api", "destination": destination, "telegram_message_id": int(message.id)}


def send_bot_api(
    destination: str,
    prepared: PreparedMessage,
    message_format: str,
    timeout: int,
    reply_to: int | None = None,
) -> dict[str, Any]:
    token = os.getenv("TELEGRAM_BOT_TOKEN", "").strip()
    if not token:
        raise RuntimeError("TELEGRAM_BOT_TOKEN is required for bot sending")
    data = {
        "chat_id": destination,
        "text": prepared.text,
        "disable_web_page_preview": "true",
    }
    if message_format == "telegram":
        if prepared.entities:
            data["entities"] = json.dumps(
                [entity.as_bot_api() for entity in prepared.entities],
                ensure_ascii=False,
            )
    else:
        mode = _bot_parse_mode(message_format)
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
    parser.add_argument(
        "--format",
        choices=["telegram", "plain", "html", "markdown", "markdownv2"],
        help="Message format. Default: telegram (native entities from safe lightweight markup).",
    )
    parser.add_argument(
        "--parse-mode",
        choices=["none", "html", "md", "markdown", "markdownv2"],
        help="Deprecated compatibility alias; use --format.",
    )
    parser.add_argument("--reply-to", type=int, help="Reply/topic root message id for forum topics")
    parser.add_argument(
        "--access-hash",
        default="",
        help="MTProto access_hash for an explicit numeric user id",
    )
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
        message_format = resolve_message_format(args.format, args.parse_mode)
        if args.file:
            if args.sender != "user":
                raise RuntimeError("--file is supported only with --sender user")
            if not Path(args.file).is_file():
                raise RuntimeError(f"attachment not found: {args.file}")
        prepared = prepare_message(text, message_format, 1024 if args.file else 3900)
        payload = {
            "status": "dry_run" if args.dry_run else "ready",
            "sender": args.sender,
            "recipient": {
                "query": recipient.query,
                "label": recipient.label,
                "destination": recipient.destination,
                "source": recipient.source,
            },
            "format": message_format,
            "reply_to": args.reply_to,
            "access_hash_supplied": bool(args.access_hash),
            "peer": peer_cache_note(recipient.destination) if args.sender == "user" and not args.access_hash else "",
            "file": args.file,
            "text": prepared.text,
            "entities": [entity.as_bot_api() for entity in prepared.entities],
        }
        if prepared.text != text:
            payload["source_text"] = text
        if args.dry_run:
            print(json.dumps(payload, ensure_ascii=False, indent=2) if args.json else _human(payload))
            return 0
        if not args.yes:
            raise RuntimeError("actual sending requires --yes; use --dry-run to preview")
        if args.sender == "user":
            try:
                result = asyncio.run(
                    asyncio.wait_for(
                        send_user_api(
                            recipient.destination,
                            prepared,
                            message_format,
                            reply_to=args.reply_to,
                            file=args.file,
                            access_hash=args.access_hash,
                        ),
                        timeout=args.timeout,
                    )
                )
            except TimeoutError as exc:
                raise RuntimeError(f"userapi send timed out after {args.timeout}s") from exc
            except asyncio.TimeoutError as exc:
                raise RuntimeError(f"userapi send timed out after {args.timeout}s") from exc
        else:
            result = send_bot_api(
                recipient.destination,
                prepared,
                message_format,
                args.timeout,
                reply_to=args.reply_to,
            )
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
        f"format: {payload['format']}",
        f"entities: {len(payload.get('entities') or [])}",
        f"reply_to: {payload.get('reply_to') or '-'}",
        *( [f"peer: {payload['peer']}"] if payload.get("peer") else [] ),
        "text:",
        payload["text"],
    ]
    result = payload.get("result")
    if result:
        lines.insert(3, f"message_id: {result.get('telegram_message_id')}")
    return "\n".join(lines)


if __name__ == "__main__":
    raise SystemExit(main())
