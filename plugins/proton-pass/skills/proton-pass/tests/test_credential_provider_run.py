from __future__ import annotations

import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


SCRIPTS = Path(__file__).parents[1] / "scripts"
sys.path.insert(0, str(SCRIPTS))
import pass_cli_agent as PASS_AGENT

SPEC = importlib.util.spec_from_file_location(
    "credential_provider_run", SCRIPTS / "credential_provider_run.py"
)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(MODULE)


CONTRACT = {
    "service": {"name": "Example Service", "aliases": ["example"]},
    "fields": {
        "SERVICE_URL": {"required": True, "aliases": ["url", "urls"]},
        "SERVICE_API_KEY": {"required": True, "aliases": ["api key", "api_key"]},
        "SERVICE_DATABASE": {"required": False, "aliases": ["database"]},
    },
}


class CredentialProviderTests(unittest.TestCase):
    def test_trashed_items_are_not_active(self) -> None:
        self.assertFalse(MODULE.item_is_active({"state": "Trashed"}))
        self.assertTrue(MODULE.item_is_active({"state": "Active"}))

    def test_extracts_names_without_returning_values(self) -> None:
        payload = {
            "item": {
                "content": {
                    "title": "Example Service API",
                    "extra_fields": [
                        {"name": "URL", "content": {"Text": "https://secret.example"}},
                        {"name": "API Key", "content": {"Hidden": "secret-key"}},
                        {"name": "Database", "content": {"Text": "secret-db"}},
                    ],
                    "content": {"Custom": {"sections": []}},
                }
            }
        }
        fields = MODULE.extract_item_field_names(payload)
        self.assertEqual(fields, ["URL", "API Key", "Database"])
        self.assertNotIn("secret-key", fields)
        self.assertEqual(
            MODULE.map_contract_fields(CONTRACT, fields),
            {
                "SERVICE_URL": "URL",
                "SERVICE_API_KEY": "API Key",
                "SERVICE_DATABASE": "Database",
            },
        )

    def test_contract_does_not_limit_consumer_operations(self) -> None:
        fields = ["URL", "API Key"]
        self.assertIsNotNone(MODULE.map_contract_fields(CONTRACT, fields))
        reference = MODULE.pass_reference("share", "item", "Section.API Key")
        self.assertEqual(reference, "pass://share/item/Section.API%20Key")

    def test_authentication_failure_marks_consumer_as_not_started(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary = Path(temporary_directory)
            fake_cli = temporary / "pass-cli"
            contract = temporary / "contract.json"
            fake_cli.write_text(
                "#!/bin/sh\nprintf 'not authenticated; run pass-cli login\\n' >&2\nexit 1\n",
                encoding="utf-8",
            )
            fake_cli.chmod(0o700)
            contract.write_text(json.dumps(CONTRACT), encoding="utf-8")
            env = os.environ.copy()
            env.update(
                {
                    "PROTON_PASS_CLI_PATH": str(fake_cli),
                    "PROTON_PASS_SESSION_DIR": str(temporary / "session"),
                    "PROTON_PASS_PERSONAL_ACCESS_TOKEN": "pst_test::test",
                }
            )
            result = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPTS / "credential_provider_run.py"),
                    "--contract",
                    str(contract),
                    "--",
                    sys.executable,
                    "-c",
                    "raise SystemExit('consumer must not run')",
                ],
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )
            self.assertEqual(result.returncode, 1)
            self.assertIn("before launching the consumer", result.stderr)
            self.assertIn("destination service was not contacted", result.stderr)
            self.assertNotIn("consumer must not run", result.stdout)

    def test_public_contract_runner_discovers_active_item_and_runs_consumer(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary = Path(temporary_directory)
            fake_cli = temporary / "pass-cli"
            contract = temporary / "contract.json"
            fake_cli.write_text(
                """#!/usr/bin/env python3
import json
import os
import subprocess
import sys
import urllib.parse

args = sys.argv[1:]
if args == [\"info\"]:
    print(\"authenticated\")
    raise SystemExit(0)
if args[:2] == [\"vault\", \"list\"]:
    print(json.dumps({\"vaults\": [{\"name\": \"Automation\", \"share_id\": \"share\", \"vault_id\": \"vault\"}]}))
    raise SystemExit(0)
if args[:2] == [\"item\", \"list\"]:
    print(json.dumps({\"items\": [
        {\"id\": \"active\", \"share_id\": \"share\", \"state\": \"Active\", \"title\": \"Example Service API\"},
        {\"id\": \"trashed\", \"share_id\": \"share\", \"state\": \"Trashed\", \"title\": \"Example Service API\"}
    ]}))
    raise SystemExit(0)
if args[:2] == [\"item\", \"view\"]:
    if \"trashed\" in args:
        raise SystemExit(9)
    print(json.dumps({\"item\": {\"content\": {
        \"title\": \"Example Service API\",
        \"extra_fields\": [
            {\"name\": \"URL\", \"content\": {\"Text\": \"https://hidden.example\"}},
            {\"name\": \"API Key\", \"content\": {\"Hidden\": \"hidden-key\"}},
            {\"name\": \"Database\", \"content\": {\"Text\": \"hidden-db\"}}
        ],
        \"content\": {\"Custom\": {\"sections\": []}}
    }}}))
    raise SystemExit(0)
if args[:1] == [\"run\"]:
    marker = args.index(\"--\")
    child_env = os.environ.copy()
    replacements = {\"URL\": \"https://hidden.example\", \"API Key\": \"hidden-key\", \"Database\": \"hidden-db\"}
    for name, value in list(child_env.items()):
        if value.startswith(\"pass://\"):
            field = urllib.parse.unquote(value.rsplit(\"/\", 1)[-1])
            child_env[name] = replacements[field]
    raise SystemExit(subprocess.run(args[marker + 1:], env=child_env, check=False).returncode)
raise SystemExit(2)
""",
                encoding="utf-8",
            )
            fake_cli.chmod(0o700)
            contract.write_text(json.dumps(CONTRACT), encoding="utf-8")
            env = os.environ.copy()
            env.update(
                {
                    "PROTON_PASS_CLI_PATH": str(fake_cli),
                    "PROTON_PASS_SESSION_DIR": str(temporary / "session"),
                }
            )
            consumer = (
                "import os; "
                "assert os.environ['SERVICE_URL'] == 'https://hidden.example'; "
                "assert os.environ['SERVICE_API_KEY'] == 'hidden-key'; "
                "assert os.environ['SERVICE_DATABASE'] == 'hidden-db'; "
                "print('consumer-ok')"
            )
            result = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPTS / "credential_provider_run.py"),
                    "--contract",
                    str(contract),
                    "--",
                    sys.executable,
                    "-c",
                    consumer,
                ],
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), "consumer-ok")
            self.assertNotIn("hidden-key", result.stdout + result.stderr)

    @unittest.skipUnless(sys.platform == "darwin", "macOS Keychain behavior")
    def test_keychain_lookup_timeout_fails_quickly(self) -> None:
        with mock.patch.object(
            PASS_AGENT,
            "run_capture",
            side_effect=subprocess.TimeoutExpired(["security"], 5),
        ) as run_capture:
            self.assertIsNone(PASS_AGENT.macos_keychain_token(os.environ.copy()))
        self.assertGreaterEqual(run_capture.call_count, 1)
        for call in run_capture.call_args_list:
            self.assertEqual(call.kwargs["timeout"], PASS_AGENT.KEYCHAIN_TIMEOUT_SECONDS)


if __name__ == "__main__":
    unittest.main()
