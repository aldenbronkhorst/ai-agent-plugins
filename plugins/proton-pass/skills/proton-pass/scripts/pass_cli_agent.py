#!/usr/bin/env python3
"""Run Proton Pass CLI with safe, portable agent-session recovery."""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys


AUTH_MARKERS = (
    "requires an authenticated client",
    "there is no session",
    "no active session",
    "non-existent session",
    "failed to authenticate",
    "not authenticated",
    "run 'pass-cli login'",
    'run "pass-cli login"',
)
TOKEN_PATTERN = re.compile(r"pst_[A-Za-z0-9_-]+::[A-Za-z0-9_-]+")
REASON_REQUIRED = {
    ("item", "view"),
    ("item", "create"),
    ("item", "update"),
    ("item", "trash"),
    ("item", "untrash"),
    ("vault", "update"),
}


def redact(text: str) -> str:
    return TOKEN_PATTERN.sub("<redacted>", text)


def pass_cli_path() -> str:
    configured = os.environ.get("PROTON_PASS_CLI_PATH")
    if configured:
        if os.path.isfile(configured) and os.access(configured, os.X_OK):
            return configured
        raise RuntimeError("PROTON_PASS_CLI_PATH is not an executable file")

    resolved = shutil.which("pass-cli") or shutil.which("pass-cli.exe")
    if not resolved:
        raise RuntimeError(
            "pass-cli is not installed or not available in PATH; see "
            "https://protonpass.github.io/pass-cli/get-started/installation/"
        )
    return resolved


def run_capture(
    argv: list[str], env: dict[str, str], timeout: int = 90
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        argv,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
        check=False,
    )


def is_auth_failure(result: subprocess.CompletedProcess[str]) -> bool:
    combined = f"{result.stdout}\n{result.stderr}".lower()
    return any(marker in combined for marker in AUTH_MARKERS)


def emit(result: subprocess.CompletedProcess[str]) -> None:
    if result.stdout:
        sys.stdout.write(redact(result.stdout))
    if result.stderr:
        sys.stderr.write(redact(result.stderr))


def reauthenticate(
    pass_cli: str, env: dict[str, str], token: str | None
) -> bool:
    logout = run_capture([pass_cli, "logout", "--force"], env)
    if logout.returncode != 0 and not is_auth_failure(logout):
        emit(logout)
        return False

    if not token:
        print(
            "Proton Pass needs authentication. Run 'pass-cli login' to use "
            "the web flow, or inject a scoped Personal Access Token through "
            "PROTON_PASS_PERSONAL_ACCESS_TOKEN for this wrapper process.",
            file=sys.stderr,
        )
        return False

    if not TOKEN_PATTERN.fullmatch(token):
        print("The supplied Proton Pass token has an invalid format.", file=sys.stderr)
        return False

    login_env = env.copy()
    login_env["PROTON_PASS_PERSONAL_ACCESS_TOKEN"] = token
    login = run_capture([pass_cli, "login"], login_env)
    login_env.pop("PROTON_PASS_PERSONAL_ACCESS_TOKEN", None)
    if login.returncode != 0:
        emit(login)
        return False

    verified = run_capture([pass_cli, "info"], env)
    if verified.returncode != 0:
        emit(verified)
        return False
    return True


def ensure_session(
    pass_cli: str, env: dict[str, str], token: str | None
) -> bool:
    status = run_capture([pass_cli, "info"], env)
    if status.returncode == 0:
        return True
    if not is_auth_failure(status):
        emit(status)
        return False
    return reauthenticate(pass_cli, env, token)


def requires_reason(arguments: list[str]) -> bool:
    return len(arguments) >= 2 and tuple(arguments[:2]) in REASON_REQUIRED


def main() -> int:
    arguments = sys.argv[1:]
    if not arguments:
        print("Usage: pass_cli_agent.py <pass-cli arguments>", file=sys.stderr)
        return 2

    if requires_reason(arguments) and not os.environ.get("PROTON_PASS_AGENT_REASON"):
        print(
            "Set PROTON_PASS_AGENT_REASON to a brief, specific reason before "
            "accessing or changing Proton Pass items.",
            file=sys.stderr,
        )
        return 2

    token = os.environ.pop("PROTON_PASS_PERSONAL_ACCESS_TOKEN", None)
    env = os.environ.copy()

    try:
        pass_cli = pass_cli_path()
        if not ensure_session(pass_cli, env, token):
            return 1

        result = run_capture([pass_cli, *arguments], env)
        if is_auth_failure(result):
            if not reauthenticate(pass_cli, env, token):
                return result.returncode or 1
            result = run_capture([pass_cli, *arguments], env)

        emit(result)
        return result.returncode
    except (OSError, RuntimeError, subprocess.SubprocessError) as exc:
        print(redact(str(exc)), file=sys.stderr)
        return 1
    finally:
        if token is not None:
            del token


if __name__ == "__main__":
    raise SystemExit(main())
