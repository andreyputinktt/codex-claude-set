from __future__ import annotations

import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "telegram_send.py"
SPEC = importlib.util.spec_from_file_location("telegram_send", SCRIPT)
assert SPEC and SPEC.loader
telegram_send = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = telegram_send
SPEC.loader.exec_module(telegram_send)


class RecipientResolutionTest(unittest.TestCase):
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

    def test_unrelated_name_does_not_match(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(RuntimeError, "recipient not found"):
                telegram_send.resolve_recipient(Path(directory), "Александр")


if __name__ == "__main__":
    unittest.main()
