#!/usr/bin/env python3
"""Run Proton Pass CLI with safe, portable agent-session recovery."""

from __future__ import annotations

import contextlib
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Iterator, Optional


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
GENERIC_KEYCHAIN = ("proton-pass-agent-bootstrap", "default")
LEGACY_KEYCHAIN = ("com.openai.codex.proton-pass-bootstrap", "codex-agent")
KEYCHAIN_TIMEOUT_SECONDS = 5


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


def agent_session_root() -> Path:
    configured = os.environ.get("PROTON_PASS_SESSION_DIR")
    if configured:
        return Path(configured).expanduser()

    home = Path.home()
    if sys.platform == "darwin":
        legacy = home / "Library/Application Support/proton-pass-cli-codex-agent"
        if legacy.is_dir():
            return legacy
        return home / "Library/Application Support/proton-pass-cli-agent"

    if os.name == "nt":
        local_data = os.environ.get("LOCALAPPDATA")
        base = Path(local_data) if local_data else home / "AppData/Local"
        return base / "proton-pass-cli-agent"

    xdg_data = os.environ.get("XDG_DATA_HOME")
    base = Path(xdg_data) if xdg_data else home / ".local/share"
    return base / "proton-pass-cli-agent"


def prepare_environment(session_root: Path) -> dict[str, str]:
    session_root.mkdir(mode=0o700, parents=True, exist_ok=True)
    if os.name != "nt":
        os.chmod(session_root, 0o700)
    env = os.environ.copy()
    env["PROTON_PASS_SESSION_DIR"] = str(session_root)
    env.pop("PROTON_PASS_PERSONAL_ACCESS_TOKEN", None)
    return env


@contextlib.contextmanager
def authentication_lock(session_root: Path) -> Iterator[None]:
    lock_path = session_root / ".authentication.lock"
    with lock_path.open("a+b") as lock:
        if os.name == "nt":
            import msvcrt

            lock.seek(0, os.SEEK_END)
            if lock.tell() == 0:
                lock.write(b"\0")
                lock.flush()
            lock.seek(0)
            msvcrt.locking(lock.fileno(), msvcrt.LK_LOCK, 1)
            try:
                yield
            finally:
                lock.seek(0)
                msvcrt.locking(lock.fileno(), msvcrt.LK_UNLCK, 1)
        else:
            import fcntl

            fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
            try:
                yield
            finally:
                fcntl.flock(lock.fileno(), fcntl.LOCK_UN)


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


def macos_keychain_token(env: dict[str, str]) -> Optional[str]:
    if sys.platform != "darwin":
        return None

    security = shutil.which("security")
    if not security:
        return None

    configured = (
        os.environ.get("PROTON_PASS_AGENT_KEYCHAIN_SERVICE", GENERIC_KEYCHAIN[0]),
        os.environ.get("PROTON_PASS_AGENT_KEYCHAIN_ACCOUNT", GENERIC_KEYCHAIN[1]),
    )
    candidates = (configured, GENERIC_KEYCHAIN, LEGACY_KEYCHAIN)
    seen: set[tuple[str, str]] = set()

    for service, account in candidates:
        if (service, account) in seen:
            continue
        seen.add((service, account))
        try:
            result = run_capture(
                [
                    security,
                    "find-generic-password",
                    "-s",
                    service,
                    "-a",
                    account,
                    "-w",
                ],
                env,
                timeout=KEYCHAIN_TIMEOUT_SECONDS,
            )
        except subprocess.TimeoutExpired:
            continue
        if result.returncode != 0:
            continue
        token = result.stdout.strip()
        if not TOKEN_PATTERN.fullmatch(token):
            raise RuntimeError(
                "The Proton Pass bootstrap token in macOS Keychain has an "
                "invalid format"
            )
        return token
    return None


def resolve_token(env: dict[str, str], injected_token: Optional[str]) -> Optional[str]:
    if injected_token:
        if not TOKEN_PATTERN.fullmatch(injected_token):
            raise RuntimeError("The supplied Proton Pass token has an invalid format")
        return injected_token
    return macos_keychain_token(env)


def recover_session(
    pass_cli: str,
    env: dict[str, str],
    session_root: Path,
    injected_token: Optional[str],
) -> bool:
    with authentication_lock(session_root):
        status = run_capture([pass_cli, "info"], env)
        if status.returncode == 0:
            return True
        if not is_auth_failure(status):
            emit(status)
            return False

        logout = run_capture([pass_cli, "logout", "--force"], env)
        if logout.returncode != 0 and not is_auth_failure(logout):
            emit(logout)
            return False

        token = resolve_token(env, injected_token)
        if not token:
            print(
                "Proton Pass needs authentication. Run 'pass-cli login' to use "
                "the web flow, or inject a scoped Personal Access Token through "
                "PROTON_PASS_PERSONAL_ACCESS_TOKEN for this wrapper process.",
                file=sys.stderr,
            )
            return False

        login_env = env.copy()
        login_env["PROTON_PASS_PERSONAL_ACCESS_TOKEN"] = token
        login = run_capture([pass_cli, "login"], login_env)
        login_env.pop("PROTON_PASS_PERSONAL_ACCESS_TOKEN", None)
        del token
        if login.returncode != 0:
            emit(login)
            return False

        verified = run_capture([pass_cli, "info"], env)
        if verified.returncode != 0:
            emit(verified)
            return False
        return True


def ensure_session(
    pass_cli: str,
    env: dict[str, str],
    session_root: Path,
    injected_token: Optional[str],
) -> bool:
    status = run_capture([pass_cli, "info"], env)
    if status.returncode == 0:
        return True
    if not is_auth_failure(status):
        emit(status)
        return False
    return recover_session(pass_cli, env, session_root, injected_token)


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

    injected_token = os.environ.pop("PROTON_PASS_PERSONAL_ACCESS_TOKEN", None)

    try:
        pass_cli = pass_cli_path()
        session_root = agent_session_root()
        env = prepare_environment(session_root)
        if not ensure_session(pass_cli, env, session_root, injected_token):
            return 1

        result = run_capture([pass_cli, *arguments], env)
        if is_auth_failure(result):
            if not recover_session(pass_cli, env, session_root, injected_token):
                return result.returncode or 1
            result = run_capture([pass_cli, *arguments], env)

        emit(result)
        return result.returncode
    except (OSError, RuntimeError, subprocess.SubprocessError) as exc:
        print(redact(str(exc)), file=sys.stderr)
        return 1
    finally:
        if injected_token is not None:
            del injected_token


if __name__ == "__main__":
    raise SystemExit(main())
