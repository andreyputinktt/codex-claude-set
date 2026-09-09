#!/usr/bin/env python3
"""Authorize a personal Telegram user session for telegram-send.

Prints a Telethon StringSession to stdout; everything else goes to stderr, so
the session can be captured with a redirect. `--check` verifies an existing
session instead of creating one.
"""
from __future__ import annotations

import argparse
import asyncio
import os
import sys
from pathlib import Path


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


def credentials() -> tuple[int, str]:
    root = Path(os.getenv("GIT_ROOT", "").strip() or Path.cwd()).expanduser()
    _load_env_file(root / ".env-telegram")
    api_id = os.getenv("TELEGRAM_API_ID") or os.getenv("TELEGRAM_USER_APP_API_ID") or ""
    api_hash = os.getenv("TELEGRAM_API_HASH") or os.getenv("TELEGRAM_USER_APP_API_HASH") or ""
    if not api_id or not api_hash:
        raise SystemExit(
            "TELEGRAM_API_ID and TELEGRAM_API_HASH are required. Take them from "
            "https://my.telegram.org and put them into $GIT_ROOT/.env-telegram."
        )
    return int(api_id), api_hash


async def _run(check: bool) -> int:
    try:
        from telethon import TelegramClient
        from telethon.sessions import StringSession
    except ImportError:
        raise SystemExit("telethon is required: python3 -m venv .venv && .venv/bin/pip install telethon")

    api_id, api_hash = credentials()
    existing = os.getenv("TELEGRAM_USER_SESSION", "").strip()
    if check and not existing:
        raise SystemExit("TELEGRAM_USER_SESSION is not set, nothing to check")

    client = TelegramClient(StringSession(existing or None), api_id, api_hash)
    await client.connect()
    try:
        if check:
            if not await client.is_user_authorized():
                print("session is NOT authorized", file=sys.stderr)
                return 1
            me = await client.get_me()
            handle = f"@{me.username}" if me.username else str(me.id)
            print(f"session ok: {me.first_name or ''} {handle}".strip(), file=sys.stderr)
            return 0
        if not await client.is_user_authorized():
            await client.start(
                phone=lambda: input("phone (+79...): ").strip(),
                code_callback=lambda: input("code from Telegram: ").strip(),
                password=lambda: input("2FA password (empty if none): ").strip() or None,
            )
        print(client.session.save())
        print("session printed to stdout. Store it as TELEGRAM_USER_SESSION, never in git.", file=sys.stderr)
        return 0
    finally:
        await client.disconnect()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="verify TELEGRAM_USER_SESSION instead of logging in")
    args = parser.parse_args()
    return asyncio.run(_run(args.check))


if __name__ == "__main__":
    raise SystemExit(main())
