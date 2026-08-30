#!/usr/bin/env python3
"""Run Proton Pass CLI with safe, portable agent-session recovery."""

from __future__ import annotations

import contextlib
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Iterator, Optional


AUTH_MARKERS = (
    "requires an authenticated client",
    "there is no session",
    "no active session",
    "non-existent session",
    "session has expired",
    "session expired",
    "invalid session",
    "session is some but is not logged in",
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
SESSION_FREE_COMMANDS = {
    "--help",
    "-h",
    "--version",
    "-V",
    "completions",
    "help",
    "update",
}
GENERIC_KEYCHAIN = ("proton-pass-agent-bootstrap", "default")
WINDOWS_CREDENTIAL_TARGET = "proton-pass-agent-bootstrap"
KEYCHAIN_TIMEOUT_SECONDS = 5
SECRET_SERVICE_TIMEOUT_SECONDS = 5


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

    if sys.platform == "win32":
        # TEMP is per-user on Windows and avoids sandbox access failures in
        # LocalAppData while remaining reusable across tasks on that host.
        temp_root = os.environ.get("TEMP") or tempfile.gettempdir()
        return Path(temp_root) / "proton-pass-cli-agent"

    if sys.platform == "darwin" or sys.platform.startswith("linux"):
        # Proton's generated agent instructions recommend an isolated temporary
        # session. The numeric user ID prevents collisions in a shared /tmp on
        # Linux while macOS normally supplies a per-user temporary directory.
        user_suffix = str(os.getuid()) if hasattr(os, "getuid") else "user"
        return Path(tempfile.gettempdir()) / f"proton-pass-cli-agent-{user_suffix}"

    return Path(tempfile.gettempdir()) / "proton-pass-cli-agent"


def prepare_environment(session_root: Path) -> dict[str, str]:
    if session_root.is_symlink():
        raise RuntimeError("Refusing to use a symlink as the Proton Pass session directory")
    if (
        sys.platform != "win32"
        and session_root.exists()
        and hasattr(os, "getuid")
        and session_root.stat().st_uid != os.getuid()
    ):
        raise RuntimeError("The Proton Pass session directory belongs to another user")
    session_root.mkdir(mode=0o700, parents=True, exist_ok=True)
    if sys.platform != "win32":
        os.chmod(session_root, 0o700)
    env = os.environ.copy()
    env["PROTON_PASS_SESSION_DIR"] = str(session_root)
    env.pop("PROTON_PASS_PERSONAL_ACCESS_TOKEN", None)
    return env


@contextlib.contextmanager
def authentication_lock(session_root: Path) -> Iterator[None]:
    lock_path = session_root / ".authentication.lock"
    with lock_path.open("a+b") as lock:
        if sys.platform == "win32":
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
        encoding="utf-8",
        errors="replace",
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

    service_override = env.get("PROTON_PASS_AGENT_KEYCHAIN_SERVICE")
    account_override = env.get("PROTON_PASS_AGENT_KEYCHAIN_ACCOUNT")
    if service_override or account_override:
        candidates = (
            (
                service_override or GENERIC_KEYCHAIN[0],
                account_override or GENERIC_KEYCHAIN[1],
            ),
        )
    else:
        candidates = (GENERIC_KEYCHAIN,)
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


def windows_credential_token() -> Optional[str]:
    """Read the device bootstrap token from Windows Credential Manager."""
    if sys.platform != "win32":
        return None

    import ctypes
    from ctypes import wintypes

    class Credential(ctypes.Structure):
        _fields_ = [
            ("Flags", wintypes.DWORD),
            ("Type", wintypes.DWORD),
            ("TargetName", wintypes.LPWSTR),
            ("Comment", wintypes.LPWSTR),
            ("LastWritten", wintypes.FILETIME),
            ("CredentialBlobSize", wintypes.DWORD),
            ("CredentialBlob", ctypes.POINTER(ctypes.c_ubyte)),
            ("Persist", wintypes.DWORD),
            ("AttributeCount", wintypes.DWORD),
            ("Attributes", ctypes.c_void_p),
            ("TargetAlias", wintypes.LPWSTR),
            ("UserName", wintypes.LPWSTR),
        ]

    target = os.environ.get(
        "PROTON_PASS_AGENT_CREDENTIAL_TARGET", WINDOWS_CREDENTIAL_TARGET
    )
    credential_pointer = ctypes.POINTER(Credential)()
    advapi32 = ctypes.WinDLL("Advapi32.dll", use_last_error=True)
    cred_read = advapi32.CredReadW
    cred_read.argtypes = [
        wintypes.LPCWSTR,
        wintypes.DWORD,
        wintypes.DWORD,
        ctypes.POINTER(ctypes.POINTER(Credential)),
    ]
    cred_read.restype = wintypes.BOOL
    if not cred_read(target, 1, 0, ctypes.byref(credential_pointer)):
        return None

    cred_free = advapi32.CredFree
    cred_free.argtypes = [ctypes.c_void_p]
    cred_free.restype = None

    try:
        credential = credential_pointer.contents
        blob = ctypes.string_at(
            credential.CredentialBlob, credential.CredentialBlobSize
        )
        token = blob.decode("utf-16-le").rstrip("\x00")
    finally:
        cred_free(credential_pointer)

    if not TOKEN_PATTERN.fullmatch(token):
        raise RuntimeError(
            "The Proton Pass bootstrap token in Windows Credential Manager "
            "has an invalid format"
        )
    return token


def linux_secret_service_token(env: dict[str, str]) -> Optional[str]:
    """Read an agent token from the desktop Secret Service when available."""
    if not sys.platform.startswith("linux"):
        return None
    secret_tool = shutil.which("secret-tool")
    if not secret_tool:
        return None
    service = env.get("PROTON_PASS_AGENT_SECRET_SERVICE", GENERIC_KEYCHAIN[0])
    account = env.get("PROTON_PASS_AGENT_SECRET_ACCOUNT", GENERIC_KEYCHAIN[1])
    try:
        result = run_capture(
            [
                secret_tool,
                "lookup",
                "service",
                service,
                "account",
                account,
            ],
            env,
            timeout=SECRET_SERVICE_TIMEOUT_SECONDS,
        )
    except subprocess.TimeoutExpired:
        return None
    if result.returncode != 0 or not result.stdout.strip():
        return None
    token = result.stdout.strip()
    if not TOKEN_PATTERN.fullmatch(token):
        raise RuntimeError(
            "The Proton Pass bootstrap token in Linux Secret Service has an "
            "invalid format"
        )
    return token


def resolve_token(env: dict[str, str], injected_token: Optional[str]) -> Optional[str]:
    if injected_token:
        if not TOKEN_PATTERN.fullmatch(injected_token):
            raise RuntimeError("The supplied Proton Pass token has an invalid format")
        return injected_token
    if sys.platform == "darwin":
        return macos_keychain_token(env)
    if sys.platform == "win32":
        return windows_credential_token()
    if sys.platform.startswith("linux"):
        return linux_secret_service_token(env)
    return None


def missing_token_message() -> str:
    if sys.platform == "darwin":
        storage = "macOS Keychain"
    elif sys.platform == "win32":
        storage = "Windows Credential Manager"
    elif sys.platform.startswith("linux"):
        storage = "Linux Secret Service or the host's secret injection"
    else:
        storage = "the host's secret injection"
    return (
        "No device-local Proton Pass agent token is configured in "
        f"{storage}. Provision a scoped agent token with the bundled "
        "proton_pass_bootstrap.py helper or inject it through "
        "PROTON_PASS_PERSONAL_ACCESS_TOKEN."
    )


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

        token = resolve_token(env, injected_token)
        if not token:
            print(missing_token_message(), file=sys.stderr)
            return False

        logout = run_capture([pass_cli, "logout", "--force"], env)
        if logout.returncode != 0 and not is_auth_failure(logout):
            emit(logout)
            return False

        login_env = env.copy()
        login_env["PROTON_PASS_PERSONAL_ACCESS_TOKEN"] = token
        login = run_capture([pass_cli, "login"], login_env)
        login_env.pop("PROTON_PASS_PERSONAL_ACCESS_TOKEN", None)
        del token
        if login.returncode != 0:
            emit(login)
            print(
                "Proton rejected the device-local agent token while creating "
                "a new two-hour CLI session. Proton's response does not "
                "distinguish an invalid, expired, or deleted token. Verify the "
                "currently issued agent token and store it on this device with "
                "proton_pass_bootstrap.py.",
                file=sys.stderr,
            )
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
    # The first status call can initialize Proton's session directory. Keep it
    # under the same cross-process lock as login so concurrent fresh agents do
    # not race while creating that directory.
    return recover_session(pass_cli, env, session_root, injected_token)


def requires_reason(arguments: list[str]) -> bool:
    return len(arguments) >= 2 and tuple(arguments[:2]) in REASON_REQUIRED


def main() -> int:
    arguments = sys.argv[1:]
    if not arguments:
        print("Usage: pass_cli_agent.py <pass-cli arguments>", file=sys.stderr)
        return 2

    if "--personal-access-token" in arguments:
        print(
            "Do not place a Proton Pass agent token in process arguments. "
            "Use device-native secure storage or "
            "PROTON_PASS_PERSONAL_ACCESS_TOKEN instead.",
            file=sys.stderr,
        )
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

        if arguments[0] in SESSION_FREE_COMMANDS:
            result = run_capture([pass_cli, *arguments], env)
            emit(result)
            return result.returncode

        # Authentication-management commands must remain usable while logged
        # out. In particular, never require a valid session before login or
        # logout can repair that session.
        if arguments[0] == "logout":
            result = run_capture([pass_cli, *arguments], env)
            emit(result)
            return result.returncode
        if arguments[0] == "login":
            token = resolve_token(env, injected_token)
            if not token and "--interactive" not in arguments:
                print(missing_token_message(), file=sys.stderr)
                return 1
            login_env = env.copy()
            if token and "--interactive" not in arguments:
                login_env["PROTON_PASS_PERSONAL_ACCESS_TOKEN"] = token
            result = run_capture([pass_cli, *arguments], login_env)
            login_env.pop("PROTON_PASS_PERSONAL_ACCESS_TOKEN", None)
            if token is not None:
                del token
            emit(result)
            return result.returncode

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
