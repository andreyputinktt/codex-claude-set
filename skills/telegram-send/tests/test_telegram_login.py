import importlib.util
import os
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

SPEC = importlib.util.spec_from_file_location(
    "telegram_login", Path(__file__).resolve().parent.parent / "scripts" / "telegram_login.py"
)
login = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(login)

TELEGRAM_ENV = ("TELEGRAM_API_ID", "TELEGRAM_API_HASH", "TELEGRAM_USER_APP_API_ID", "TELEGRAM_USER_APP_API_HASH", "GIT_ROOT")


class CredentialsTest(unittest.TestCase):
    def setUp(self) -> None:
        self.saved = {name: os.environ.pop(name, None) for name in TELEGRAM_ENV}

    def tearDown(self) -> None:
        for name, value in self.saved.items():
            os.environ.pop(name, None)
            if value is not None:
                os.environ[name] = value

    def test_missing_credentials_fail(self) -> None:
        with TemporaryDirectory() as tmp:
            os.environ["GIT_ROOT"] = tmp
            with self.assertRaises(SystemExit):
                login.credentials()

    def test_credentials_read_from_env_file(self) -> None:
        with TemporaryDirectory() as tmp:
            (Path(tmp) / ".env-telegram").write_text("TELEGRAM_API_ID=123\nTELEGRAM_API_HASH=abc\n", encoding="utf-8")
            os.environ["GIT_ROOT"] = tmp
            self.assertEqual(login.credentials(), (123, "abc"))


if __name__ == "__main__":
    unittest.main()
