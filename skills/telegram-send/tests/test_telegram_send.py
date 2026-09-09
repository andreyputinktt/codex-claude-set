from __future__ import annotations

import importlib.util
import json
import os
import sys
import tempfile
import unittest
import urllib.parse
from pathlib import Path
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "telegram_send.py"
SPEC = importlib.util.spec_from_file_location("telegram_send", SCRIPT)
assert SPEC and SPEC.loader
telegram_send = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = telegram_send
SPEC.loader.exec_module(telegram_send)


class RecipientResolutionTest(unittest.TestCase):
    """Resolution must not reach the account's real dialog cache."""

    def setUp(self) -> None:
        self._cache = tempfile.TemporaryDirectory()
        self._saved = os.environ.get("TELEGRAM_DIALOG_CACHE")
        os.environ["TELEGRAM_DIALOG_CACHE"] = str(Path(self._cache.name) / "dialogs.json")

    def tearDown(self) -> None:
        if self._saved is None:
            os.environ.pop("TELEGRAM_DIALOG_CACHE", None)
        else:
            os.environ["TELEGRAM_DIALOG_CACHE"] = self._saved
        self._cache.cleanup()

    def test_timofeev_formats_resolve_to_same_username(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for query in (
                "Тимофеев",
                "Тимофееву",
                "Алексей Тимофеев",
                "Алексею Тимофееву",
                "Alexey Timofeev",
                "alekstim84",
            ):
                with self.subTest(query=query):
                    recipient = telegram_send.resolve_recipient(root, query)
                    self.assertEqual(recipient.destination, "@alekstim84")

    def test_explicit_username_stays_explicit(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            recipient = telegram_send.resolve_recipient(Path(directory), "@alekstim84")
        self.assertEqual(recipient.source, "explicit")

    def test_state_chat_name_resolves_from_a_russian_case_form(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            state = root / "assistants" / "telegram-chats"
            state.mkdir(parents=True)
            (state / "state.json").write_text(
                json.dumps({"chats": {"LadaIkonnikova": {"chat_id": "@ladanoframes"}}}),
                encoding="utf-8",
            )
            recipient = telegram_send.resolve_recipient(root, "Иконниковой")
        self.assertEqual(recipient.destination, "@ladanoframes")

    def test_unrelated_name_does_not_match(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(RuntimeError, "recipient not found"):
                telegram_send.resolve_recipient(Path(directory), "Александр")


class TelegramFormattingTest(unittest.TestCase):
    def test_default_format_is_telegram(self) -> None:
        self.assertEqual(telegram_send.resolve_message_format(None, None), "telegram")

    def test_explicit_formats_override_default(self) -> None:
        self.assertEqual(telegram_send.resolve_message_format("plain", None), "plain")
        self.assertEqual(telegram_send.resolve_message_format("html", None), "html")
        self.assertEqual(telegram_send.resolve_message_format(None, "none"), "plain")
        self.assertEqual(telegram_send.resolve_message_format(None, "md"), "markdown")

    def test_conflicting_format_options_fail(self) -> None:
        with self.assertRaisesRegex(RuntimeError, "either --format"):
            telegram_send.resolve_message_format("telegram", "html")

    def test_native_entities_and_clean_text(self) -> None:
        prepared = telegram_send.prepare_telegram_message(
            "🚀 **Важно**\n\n• [Открыть заявку](https://example.com)\n• `case-42`"
        )
        self.assertEqual(prepared.text, "🚀 Важно\n\n• Открыть заявку\n• case-42")
        self.assertEqual(
            [entity.as_bot_api() for entity in prepared.entities],
            [
                {"type": "bold", "offset": 3, "length": 5},
                {
                    "type": "text_link",
                    "offset": 12,
                    "length": 14,
                    "url": "https://example.com",
                },
                {"type": "code", "offset": 29, "length": 7},
            ],
        )

    def test_plain_format_preserves_source_markup(self) -> None:
        prepared = telegram_send.prepare_message("**Не выделять**", "plain", 3900)
        self.assertEqual(prepared.text, "**Не выделять**")
        self.assertEqual(prepared.entities, ())

    def test_default_format_does_not_treat_identifiers_as_italic(self) -> None:
        prepared = telegram_send.prepare_telegram_message("case_id и first_last")
        self.assertEqual(prepared.text, "case_id и first_last")
        self.assertEqual(prepared.entities, ())

    def test_bot_api_uses_native_entities_for_telegram_format(self) -> None:
        prepared = telegram_send.prepare_telegram_message("**Важно**")

        class Response:
            def __enter__(self) -> "Response":
                return self

            def __exit__(self, *_args: object) -> None:
                return None

            def read(self) -> bytes:
                return b'{"ok": true, "result": {"message_id": 42}}'

        captured: dict[str, str] = {}

        def fake_urlopen(request: object, timeout: int) -> Response:
            self.assertEqual(timeout, 5)
            captured.update(
                urllib.parse.parse_qsl(
                    request.data.decode(),  # type: ignore[attr-defined]
                    keep_blank_values=True,
                )
            )
            return Response()

        with patch.dict(os.environ, {"TELEGRAM_BOT_TOKEN": "test-token"}):
            with patch.object(telegram_send.urllib.request, "urlopen", fake_urlopen):
                telegram_send.send_bot_api("@example", prepared, "telegram", 5)

        self.assertNotIn("parse_mode", captured)
        self.assertEqual(
            json.loads(captured["entities"]),
            [{"type": "bold", "offset": 0, "length": 5}],
        )


if __name__ == "__main__":
    unittest.main()


class CachedPeerTests(unittest.TestCase):
    class _Session:
        def __init__(self, known):
            self.known = known

        def get_input_entity(self, value):
            if value in self.known:
                return f"cached:{value}"
            raise ValueError("not found")

    def test_supergroup_id_maps_to_channel(self) -> None:
        entity = telegram_send.cached_peer(
            self._Session({}), "-1001234567890", lambda i: ("channel", i), lambda i: ("chat", i)
        )
        self.assertEqual(entity, ("channel", 1234567890))

    def test_legacy_group_id_maps_to_chat(self) -> None:
        entity = telegram_send.cached_peer(
            self._Session({}), "-4242", lambda i: ("channel", i), lambda i: ("chat", i)
        )
        self.assertEqual(entity, ("chat", 4242))

    def test_cached_user_id_resolves_offline(self) -> None:
        entity = telegram_send.cached_peer(
            self._Session({777}), "777", lambda i: ("channel", i), lambda i: ("chat", i)
        )
        self.assertEqual(entity, "cached:777")

    def test_unknown_user_id_fails_fast_instead_of_scanning_contacts(self) -> None:
        with self.assertRaises(RuntimeError) as ctx:
            telegram_send.cached_peer(
                self._Session({}), "3754743216", lambda i: ("channel", i), lambda i: ("chat", i)
            )
        self.assertIn("--access-hash", str(ctx.exception))

    def test_phone_resolves_from_cache(self) -> None:
        entity = telegram_send.cached_peer(
            self._Session({"+79990000000"}), "+79990000000", lambda i: ("channel", i), lambda i: ("chat", i)
        )
        self.assertEqual(entity, "cached:+79990000000")

    def test_username_is_not_routed_through_the_cache(self) -> None:
        self.assertFalse(telegram_send.needs_cache_lookup("@alekstim84"))
        self.assertTrue(telegram_send.needs_cache_lookup("3754743216"))
        self.assertTrue(telegram_send.needs_cache_lookup("+79990000000"))

    def test_cache_note_skips_usernames_and_explains_group_ids(self) -> None:
        self.assertEqual(telegram_send.peer_cache_note("@alekstim84"), "")
        self.assertEqual(
            telegram_send.peer_cache_note("-1001234567890"), "group or channel id, no lookup needed"
        )
