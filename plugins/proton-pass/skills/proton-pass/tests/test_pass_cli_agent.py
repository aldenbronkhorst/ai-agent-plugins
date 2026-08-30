from __future__ import annotations

import importlib.util
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


SCRIPTS = Path(__file__).parents[1] / "scripts"
sys.path.insert(0, str(SCRIPTS))
import pass_cli_agent as AGENT

BOOTSTRAP_SPEC = importlib.util.spec_from_file_location(
    "proton_pass_bootstrap", SCRIPTS / "proton_pass_bootstrap.py"
)
BOOTSTRAP = importlib.util.module_from_spec(BOOTSTRAP_SPEC)
assert BOOTSTRAP_SPEC.loader is not None
BOOTSTRAP_SPEC.loader.exec_module(BOOTSTRAP)


FAKE_CLI = r'''#!/usr/bin/env python3
import os
import sys
from pathlib import Path

state = Path(os.environ["FAKE_STATE"])
log = Path(os.environ["FAKE_LOG"])
args = sys.argv[1:]
with log.open("a", encoding="utf-8") as handle:
    handle.write(" ".join(args) + "\n")

if args == ["info"]:
    if state.exists():
        print("authenticated")
        raise SystemExit(0)
    print("This operation requires an authenticated client", file=sys.stderr)
    raise SystemExit(1)
if args == ["logout", "--force"]:
    state.unlink(missing_ok=True)
    raise SystemExit(0)
if args == ["login"]:
    token = os.environ.get("PROTON_PASS_PERSONAL_ACCESS_TOKEN")
    if token == "pst_valid::valid":
        state.write_text("authenticated", encoding="utf-8")
        print("logged in")
        raise SystemExit(0)
    print("This personal access token is invalid, expired or has been deleted", file=sys.stderr)
    raise SystemExit(1)
if args in (["--version"], ["update", "--yes"]):
    print("pass-cli test version")
    raise SystemExit(0)
if state.exists():
    if os.environ.get("PROTON_PASS_PERSONAL_ACCESS_TOKEN"):
        print("token remained in consumer environment", file=sys.stderr)
        raise SystemExit(3)
    print("requested-command-ok")
    raise SystemExit(0)
print("This operation requires an authenticated client", file=sys.stderr)
raise SystemExit(1)
'''


FAKE_CONCURRENT_CLI = r'''#!/usr/bin/env python3
import os
import sys
import time
from pathlib import Path

state = Path(os.environ["FAKE_STATE"])
busy = Path(os.environ["FAKE_BUSY"])
log = Path(os.environ["FAKE_LOG"])
args = sys.argv[1:]
with log.open("a", encoding="utf-8") as handle:
    handle.write(" ".join(args) + "\n")

if args == ["info"]:
    try:
        busy.mkdir()
    except FileExistsError:
        print("Cannot create a file when that file already exists", file=sys.stderr)
        raise SystemExit(7)
    try:
        time.sleep(0.1)
        if state.exists():
            print("authenticated")
            raise SystemExit(0)
        print("This operation requires an authenticated client", file=sys.stderr)
        raise SystemExit(1)
    finally:
        busy.rmdir()
if args == ["logout", "--force"]:
    state.unlink(missing_ok=True)
    raise SystemExit(0)
if args == ["login"]:
    if os.environ.get("PROTON_PASS_PERSONAL_ACCESS_TOKEN") != "pst_valid::valid":
        raise SystemExit(1)
    state.write_text("authenticated", encoding="utf-8")
    raise SystemExit(0)
if state.exists():
    print("requested-command-ok")
    raise SystemExit(0)
raise SystemExit(1)
'''


class PassCliAgentTests(unittest.TestCase):
    def run_wrapper(self, token: str | None, *arguments: str) -> tuple[subprocess.CompletedProcess[str], list[str]]:
        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary = Path(temporary_directory)
            fake_cli = temporary / "pass-cli"
            state = temporary / "state"
            log = temporary / "calls.log"
            fake_cli.write_text(FAKE_CLI, encoding="utf-8")
            fake_cli.chmod(0o700)
            env = os.environ.copy()
            env.update(
                {
                    "PROTON_PASS_CLI_PATH": str(fake_cli),
                    "PROTON_PASS_SESSION_DIR": str(temporary / "session"),
                    "PROTON_PASS_AGENT_KEYCHAIN_SERVICE": "test-proton-pass-agent",
                    "PROTON_PASS_AGENT_KEYCHAIN_ACCOUNT": "test",
                    "PROTON_PASS_AGENT_CREDENTIAL_TARGET": "test-proton-pass-agent",
                    "PROTON_PASS_AGENT_SECRET_SERVICE": "test-proton-pass-agent",
                    "PROTON_PASS_AGENT_SECRET_ACCOUNT": "test",
                    "FAKE_STATE": str(state),
                    "FAKE_LOG": str(log),
                }
            )
            if token is not None:
                env["PROTON_PASS_PERSONAL_ACCESS_TOKEN"] = token
            else:
                env.pop("PROTON_PASS_PERSONAL_ACCESS_TOKEN", None)
            result = subprocess.run(
                [sys.executable, str(SCRIPTS / "pass_cli_agent.py"), *arguments],
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )
            calls = log.read_text("utf-8").splitlines() if log.exists() else []
            return result, calls

    def test_expired_session_reauthenticates_and_retries_automatically(self) -> None:
        result, calls = self.run_wrapper(
            "pst_valid::valid", "vault", "list", "--output", "json"
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("requested-command-ok", result.stdout)
        self.assertEqual(
            calls,
            [
                "info",
                "logout --force",
                "login",
                "info",
                "vault list --output json",
            ],
        )
        self.assertNotIn("pst_valid", result.stdout + result.stderr + "\n".join(calls))

    def test_concurrent_fresh_agents_serialize_initial_session_creation(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary = Path(temporary_directory)
            fake_cli = temporary / "pass-cli"
            state = temporary / "state"
            busy = temporary / "info-busy"
            log = temporary / "calls.log"
            fake_cli.write_text(FAKE_CONCURRENT_CLI, encoding="utf-8")
            fake_cli.chmod(0o700)
            env = os.environ.copy()
            env.update(
                {
                    "PROTON_PASS_CLI_PATH": str(fake_cli),
                    "PROTON_PASS_SESSION_DIR": str(temporary / "session"),
                    "PROTON_PASS_PERSONAL_ACCESS_TOKEN": "pst_valid::valid",
                    "FAKE_STATE": str(state),
                    "FAKE_BUSY": str(busy),
                    "FAKE_LOG": str(log),
                }
            )
            processes = [
                subprocess.Popen(
                    [
                        sys.executable,
                        str(SCRIPTS / "pass_cli_agent.py"),
                        "vault",
                        "list",
                        "--output",
                        "json",
                    ],
                    env=env,
                    text=True,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                )
                for _ in range(3)
            ]
            results = [process.communicate(timeout=10) for process in processes]

            for process, (stdout, stderr) in zip(processes, results):
                self.assertEqual(process.returncode, 0, stderr)
                self.assertIn("requested-command-ok", stdout)
                self.assertNotIn("already exists", stderr.lower())
            calls = log.read_text("utf-8").splitlines()
            self.assertEqual(calls.count("login"), 1)

    def test_rejected_bootstrap_token_fails_without_exposing_it(self) -> None:
        result, calls = self.run_wrapper(
            "pst_invalid::invalid", "vault", "list", "--output", "json"
        )
        self.assertEqual(result.returncode, 1)
        self.assertIn("Proton rejected the device-local agent token", result.stderr)
        self.assertIn("does not distinguish", result.stderr)
        self.assertNotIn("pst_invalid", result.stdout + result.stderr + "\n".join(calls))

    def test_login_is_not_blocked_by_session_preflight(self) -> None:
        result, calls = self.run_wrapper("pst_valid::valid", "login")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls, ["login"])

    def test_logout_is_not_blocked_by_session_preflight(self) -> None:
        result, calls = self.run_wrapper(None, "logout", "--force")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls, ["logout --force"])

    def test_version_and_update_do_not_require_session_preflight(self) -> None:
        version_result, version_calls = self.run_wrapper(None, "--version")
        update_result, update_calls = self.run_wrapper(None, "update", "--yes")
        self.assertEqual(version_result.returncode, 0, version_result.stderr)
        self.assertEqual(update_result.returncode, 0, update_result.stderr)
        self.assertEqual(version_calls, ["--version"])
        self.assertEqual(update_calls, ["update --yes"])

    def test_login_without_token_does_not_start_web_flow(self) -> None:
        result, calls = self.run_wrapper(None, "login")
        self.assertEqual(result.returncode, 1)
        self.assertIn("No device-local", result.stderr)
        self.assertEqual(calls, [])

    def test_windows_credential_manager_is_a_token_source(self) -> None:
        with mock.patch.object(AGENT.sys, "platform", "win32"), mock.patch.object(
            AGENT, "windows_credential_token", return_value="pst_windows::token"
        ):
            self.assertEqual(
                AGENT.resolve_token({}, None), "pst_windows::token"
            )

    def test_windows_session_uses_per_user_temporary_directory(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory, mock.patch.object(
            AGENT.sys, "platform", "win32"
        ), mock.patch.dict(
            AGENT.os.environ,
            {"TEMP": temporary_directory, "LOCALAPPDATA": "C:/protected"},
            clear=False,
        ):
            AGENT.os.environ.pop("PROTON_PASS_SESSION_DIR", None)
            self.assertEqual(
                AGENT.agent_session_root(),
                Path(temporary_directory) / "proton-pass-cli-agent",
            )

    def test_linux_session_uses_isolated_per_user_temporary_directory(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory, mock.patch.object(
            AGENT.sys, "platform", "linux"
        ), mock.patch.object(
            AGENT.tempfile, "gettempdir", return_value=temporary_directory
        ), mock.patch.dict(AGENT.os.environ, {}, clear=False):
            AGENT.os.environ.pop("PROTON_PASS_SESSION_DIR", None)
            self.assertEqual(
                AGENT.agent_session_root(),
                Path(temporary_directory)
                / f"proton-pass-cli-agent-{AGENT.os.getuid()}",
            )

    def test_linux_secret_service_is_a_token_source(self) -> None:
        completed = subprocess.CompletedProcess([], 0, "pst_linux::token\n", "")
        with mock.patch.object(AGENT.sys, "platform", "linux"), mock.patch.object(
            AGENT.shutil, "which", return_value="/usr/bin/secret-tool"
        ), mock.patch.object(AGENT, "run_capture", return_value=completed):
            self.assertEqual(
                AGENT.resolve_token(os.environ.copy(), None), "pst_linux::token"
            )

    def test_macos_session_uses_isolated_temporary_directory(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory, mock.patch.object(
            AGENT.sys, "platform", "darwin"
        ), mock.patch.object(
            AGENT.tempfile, "gettempdir", return_value=temporary_directory
        ), mock.patch.dict(AGENT.os.environ, {}, clear=False):
            AGENT.os.environ.pop("PROTON_PASS_SESSION_DIR", None)
            self.assertEqual(
                AGENT.agent_session_root(),
                Path(temporary_directory)
                / f"proton-pass-cli-agent-{AGENT.os.getuid()}",
            )

    def test_macos_bootstrap_keeps_token_out_of_process_arguments(self) -> None:
        completed = subprocess.CompletedProcess([], 0, "", "")
        with mock.patch.object(
            BOOTSTRAP.shutil, "which", return_value="/usr/bin/security"
        ), mock.patch.object(
            BOOTSTRAP.subprocess, "run", return_value=completed
        ) as run:
            BOOTSTRAP.store_macos("pst_secret::secret")
        arguments = run.call_args.args[0]
        self.assertNotIn("pst_secret::secret", arguments)
        self.assertEqual(
            run.call_args.kwargs["input"],
            "pst_secret::secret\npst_secret::secret\n",
        )

    def test_linux_bootstrap_keeps_token_out_of_process_arguments(self) -> None:
        completed = subprocess.CompletedProcess([], 0, "", "")
        with mock.patch.object(
            BOOTSTRAP.shutil, "which", return_value="/usr/bin/secret-tool"
        ), mock.patch.object(
            BOOTSTRAP.subprocess, "run", return_value=completed
        ) as run:
            BOOTSTRAP.store_linux("pst_secret::secret")
        arguments = run.call_args.args[0]
        self.assertNotIn("pst_secret::secret", arguments)
        self.assertEqual(run.call_args.kwargs["input"], "pst_secret::secret\n")

    def test_rejects_token_in_process_arguments(self) -> None:
        result, calls = self.run_wrapper(
            None, "login", "--personal-access-token", "pst_secret::secret"
        )
        self.assertEqual(result.returncode, 2)
        self.assertIn("Do not place", result.stderr)
        self.assertNotIn("pst_secret", result.stdout + result.stderr)
        self.assertEqual(calls, [])

    def test_missing_token_message_does_not_default_to_browser_login(self) -> None:
        with mock.patch.object(AGENT.sys, "platform", "darwin"):
            message = AGENT.missing_token_message()
        self.assertIn("macOS Keychain", message)
        self.assertNotIn("web", message.lower())
        self.assertNotIn("browser", message.lower())


if __name__ == "__main__":
    unittest.main()
