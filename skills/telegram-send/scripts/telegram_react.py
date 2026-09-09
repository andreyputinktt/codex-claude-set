#!/usr/bin/env python3
"""Put an emoji reaction on a real Telegram message, from the user account.

A reaction is the cheapest possible acknowledgement: it says "read, nothing to
add" without reopening a finished conversation. It is also the one Telegram
write with no undo notification, so this script defaults to a dry run and shows
exactly which message it is about to touch.

    telegram_react.py list @kt_team_it --limit 10
    telegram_react.py react @kt_team_it --message-id 4211 --emoji 👍
    telegram_react.py react @kt_team_it --message-id 4211 --emoji 👍 --yes
    telegram_react.py clear @kt_team_it --message-id 4211 --yes

Session and credentials come from the same place as telegram_send.py, so
whoever that session belongs to is who the reaction comes from.
"""

from __future__ import annotations

import argparse
import asyncio
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from telegram_send import _repo_root, _user_session_file, load_env  # noqa: E402

# Telegram rejects anything outside the set a chat allows, and a rejected
# reaction reads in the log like a broken session. These are the ones every
# private chat accepts.
ALLOWED = ("👍", "🙏", "❤", "❤️", "🔥", "🎉", "👌", "👏", "😁", "🤔")


def _client():
    from telethon import TelegramClient
    from telethon.sessions import StringSession

    load_env(_repo_root())
    api_id = os.getenv("TELEGRAM_API_ID") or os.getenv("TELEGRAM_USER_APP_API_ID") or ""
    api_hash = (
        os.getenv("TELEGRAM_API_HASH") or os.getenv("TELEGRAM_USER_APP_API_HASH") or ""
    )
    if not api_id or not api_hash:
        raise RuntimeError("TELEGRAM_API_ID/TELEGRAM_API_HASH are not configured")
    string_session = os.getenv("TELEGRAM_USER_SESSION", "").strip()
    if string_session:
        return TelegramClient(StringSession(string_session), int(api_id), api_hash)
    path = _user_session_file()
    if path is None:
        raise RuntimeError("no Telethon session found; run telegram_send.py first")
    return TelegramClient(str(path.with_suffix("")), int(api_id), api_hash)


def _reactions(message) -> list[str]:
    found = []
    for item in getattr(getattr(message, "reactions", None), "results", None) or []:
        emoticon = getattr(item.reaction, "emoticon", "")
        found.append(f"{emoticon}×{item.count}")
    return found


async def _list(peer: str, limit: int) -> int:
    async with _client() as client:
        me = await client.get_me()
        print(f"сессия: @{me.username or me.id}")
        async for message in client.iter_messages(peer, limit=limit):
            if not message.text and not message.media:
                continue
            who = "я" if message.out else peer
            body = (message.text or "[медиа]").replace("\n", " ")[:90]
            marks = " ".join(_reactions(message))
            print(
                f"  id={message.id:<8} {message.date:%d.%m %H:%M} {who:<14} {body}"
                + (f"   [{marks}]" if marks else "")
            )
    return 0


async def _react(peer: str, message_id: int, emoji: str, apply: bool) -> int:
    from telethon.tl.functions.messages import SendReactionRequest
    from telethon.tl.types import ReactionEmoji

    if emoji and emoji not in ALLOWED:
        print(f"эмодзи {emoji} вне разрешённого набора: {' '.join(ALLOWED)}")
        return 2
    async with _client() as client:
        me = await client.get_me()
        message = await client.get_messages(peer, ids=message_id)
        if not message:
            print(f"сообщения {message_id} нет в диалоге {peer}")
            return 1
        body = (message.text or "[медиа]").replace("\n", " ")[:120]
        print(f"от кого реакция: @{me.username or me.id}")
        print(f"сообщение {message.id} от {message.date:%d.%m %H:%M}: {body}")
        print(f"реакции сейчас: {' '.join(_reactions(message)) or 'нет'}")
        print(f"действие: {'поставить ' + emoji if emoji else 'снять реакцию'}")
        if not apply:
            print("dry run; повторите с --yes")
            return 0
        await client(
            SendReactionRequest(
                peer=await client.get_input_entity(peer),
                msg_id=message_id,
                reaction=[ReactionEmoji(emoticon=emoji)] if emoji else [],
            )
        )
        # Read it back: the request returning without an error is not proof the
        # reaction is on the message.
        again = await client.get_messages(peer, ids=message_id)
        marks = _reactions(again)
        print(f"реакции после: {' '.join(marks) or 'нет'}")
        if emoji and not any(emoji.rstrip("️") in mark for mark in marks):
            print("реакция не подтвердилась")
            return 1
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    listing = sub.add_parser("list", help="последние сообщения диалога с их id")
    listing.add_argument("peer")
    listing.add_argument("--limit", type=int, default=10)
    for name in ("react", "clear"):
        item = sub.add_parser(name)
        item.add_argument("peer")
        item.add_argument("--message-id", type=int, required=True)
        if name == "react":
            item.add_argument("--emoji", default="👍")
        item.add_argument("--yes", action="store_true")
    args = parser.parse_args(argv)
    if args.command == "list":
        return asyncio.run(_list(args.peer, args.limit))
    emoji = getattr(args, "emoji", "")
    return asyncio.run(_react(args.peer, args.message_id, emoji, args.yes))


if __name__ == "__main__":
    raise SystemExit(main())
