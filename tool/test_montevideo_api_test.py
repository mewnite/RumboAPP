import tempfile
import unittest
from pathlib import Path

from tool.test_montevideo_api import load_env, redact


class MontevideoApiToolTest(unittest.TestCase):
    def test_env_parser_reads_credentials_without_exposing_them(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            env_file = Path(directory) / ".env"
            env_file.write_text(
                "# local credentials\nCLIENT_ID=\"client-id\"\n"
                "CLIENT_SECRET='client-secret'\n",
                encoding="utf-8",
            )

            self.assertEqual(
                load_env(env_file),
                {
                    "CLIENT_ID": "client-id",
                    "CLIENT_SECRET": "client-secret",
                },
            )

    def test_redacts_oauth_fields_recursively(self) -> None:
        self.assertEqual(
            redact(
                {
                    "access_token": "secret",
                    "vehicles": [
                        {"line": "522", "authorization": "secret"},
                    ],
                }
            ),
            {
                "access_token": "[REDACTADO]",
                "vehicles": [
                    {"line": "522", "authorization": "[REDACTADO]"},
                ],
            },
        )


if __name__ == "__main__":
    unittest.main()
