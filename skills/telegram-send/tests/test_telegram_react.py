"""The reaction script: what it refuses, and how it renders a dialog."""

from __future__ import annotations

import sys
from pathlib import Path
from types import SimpleNamespace

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))

import telegram_react  # noqa: E402


def test_an_emoji_the_chat_would_reject_never_reaches_telegram(capsys):
    """Telegram отвергает реакцию вне разрешённого набора, и в логе это
    выглядит как сломанная сессия, а не как опечатка в эмодзи."""
    assert telegram_react.main(["react", "@kt_team_it", "--message-id", "1", "--emoji", "🍆"]) == 2
    assert "вне разрешённого набора" in capsys.readouterr().out


def test_the_reactions_already_on_a_message_are_shown_with_their_counts():
    message = SimpleNamespace(
        reactions=SimpleNamespace(
            results=[
                SimpleNamespace(reaction=SimpleNamespace(emoticon="👍"), count=2),
                SimpleNamespace(reaction=SimpleNamespace(emoticon="🔥"), count=1),
            ]
        )
    )

    assert telegram_react._reactions(message) == ["👍×2", "🔥×1"]
    assert telegram_react._reactions(SimpleNamespace(reactions=None)) == []
