from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "telegram_read.py"
SPEC = importlib.util.spec_from_file_location("telegram_read", SCRIPT)
assert SPEC and SPEC.loader
telegram_read = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = telegram_read
SPEC.loader.exec_module(telegram_read)


CHATS = [
    {"id": 4589016609, "is_user": False, "name": "D3 Актив / КТ", "username": ""},
    {"id": 1653598715, "is_user": False, "name": "D3-FINANCE", "username": ""},
    {"id": 6822003966, "is_user": True, "name": "Бухгалтерия Офис Актив", "username": "@finance_active"},
    {"id": 158222723, "is_user": True, "name": "Anton Kopkin", "username": "@KopkinAnton"},
]


class MatchChatsTest(unittest.TestCase):
    def test_approximate_name_matches_by_tokens(self) -> None:
        hits = telegram_read.match_chats(CHATS, "d3 актив")
        self.assertEqual([c["id"] for c in hits], [4589016609])

    def test_match_is_case_insensitive_and_unordered(self) -> None:
        hits = telegram_read.match_chats(CHATS, "АКТИВ d3")
        self.assertEqual([c["id"] for c in hits], [4589016609])

    def test_username_and_id_are_searchable(self) -> None:
        self.assertEqual(
            [c["id"] for c in telegram_read.match_chats(CHATS, "finance_active")],
            [6822003966],
        )
        self.assertEqual(
            [c["id"] for c in telegram_read.match_chats(CHATS, "4589016609")],
            [4589016609],
        )

    def test_ambiguous_query_returns_every_candidate(self) -> None:
        hits = telegram_read.match_chats(CHATS, "актив")
        self.assertEqual({c["id"] for c in hits}, {4589016609, 6822003966})

    def test_transliterated_query_matches_cyrillic_name(self) -> None:
        hits = telegram_read.match_chats(CHATS, "D3 Aktiv / KT")
        self.assertIn(4589016609, [c["id"] for c in hits])

    def test_russian_case_form_matches_glued_latin_name(self) -> None:
        hits = telegram_read.match_chats(CHATS, "Копкину")
        self.assertEqual([c["id"] for c in hits], [158222723])

    def test_no_match_returns_nothing(self) -> None:
        self.assertEqual(telegram_read.match_chats(CHATS, "zzz qqq"), [])

    def test_near_miss_name_does_not_match(self) -> None:
        self.assertEqual(telegram_read.match_chats(CHATS, "Александр"), [])


if __name__ == "__main__":
    unittest.main()
