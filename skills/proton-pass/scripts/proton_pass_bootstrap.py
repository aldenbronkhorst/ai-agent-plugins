#!/usr/bin/env python3
"""Store a Proton Pass agent token in this device's native credential store."""

from __future__ import annotations

import argparse
import getpass
import os
import shutil
import subprocess
import sys

from pass_cli_agent import (
    GENERIC_KEYCHAIN,
    TOKEN_PATTERN,
    WINDOWS_CREDENTIAL_TARGET,
    linux_secret_service_token,
    macos_keychain_token,
    windows_credential_token,
)


def token_from_environment_or_prompt() -> str:
    token = os.environ.pop("PROTON_PASS_PERSONAL_ACCESS_TOKEN", None)
    if token is None:
        token = getpass.getpass("Proton Pass agent token: ")
    token = token.strip()
    if not TOKEN_PATTERN.fullmatch(token):
        raise RuntimeError("The supplied Proton Pass agent token has an invalid format")
    return token


def store_macos(token: str) -> None:
    security = shutil.which("security")
    if not security:
        raise RuntimeError("The macOS security command is unavailable")
    service = os.environ.get(
        "PROTON_PASS_AGENT_KEYCHAIN_SERVICE", GENERIC_KEYCHAIN[0]
    )
    account = os.environ.get(
        "PROTON_PASS_AGENT_KEYCHAIN_ACCOUNT", GENERIC_KEYCHAIN[1]
    )
    # Omitting the value after -w makes `security` read it securely. It asks
    # twice when creating/updating an item, so provide the same value twice on
    # stdin and keep it out of argv and process listings.
    result = subprocess.run(
        [
            security,
            "add-generic-password",
            "-U",
            "-s",
            service,
            "-a",
            account,
            "-l",
            "Proton Pass agent bootstrap token",
            "-w",
        ],
        input=f"{token}\n{token}\n",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or "Unable to update macOS Keychain")


def store_windows(token: str) -> None:
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
    encoded = token.encode("utf-16-le")
    blob = (ctypes.c_ubyte * len(encoded)).from_buffer_copy(encoded)
    credential = Credential()
    credential.Type = 1  # CRED_TYPE_GENERIC
    credential.TargetName = target
    credential.CredentialBlobSize = len(encoded)
    credential.CredentialBlob = ctypes.cast(blob, ctypes.POINTER(ctypes.c_ubyte))
    credential.Persist = 2  # CRED_PERSIST_LOCAL_MACHINE
    credential.UserName = "default"

    advapi32 = ctypes.WinDLL("Advapi32.dll", use_last_error=True)
    cred_write = advapi32.CredWriteW
    cred_write.argtypes = [ctypes.POINTER(Credential), wintypes.DWORD]
    cred_write.restype = wintypes.BOOL
    if not cred_write(ctypes.byref(credential), 0):
        raise ctypes.WinError(ctypes.get_last_error())


def store_linux(token: str) -> None:
    secret_tool = shutil.which("secret-tool")
    if not secret_tool:
        raise RuntimeError(
            "Linux Secret Service is unavailable; inject the agent token "
            "through the host's secure secret mechanism"
        )
    service = os.environ.get("PROTON_PASS_AGENT_SECRET_SERVICE", GENERIC_KEYCHAIN[0])
    account = os.environ.get("PROTON_PASS_AGENT_SECRET_ACCOUNT", GENERIC_KEYCHAIN[1])
    result = subprocess.run(
        [
            secret_tool,
            "store",
            "--label=Proton Pass agent bootstrap token",
            "service",
            service,
            "account",
            account,
        ],
        input=f"{token}\n",
        text=True,
        encoding="utf-8",
        errors="replace",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or "Unable to update Linux Secret Service")


def store() -> None:
    token = token_from_environment_or_prompt()
    try:
        if sys.platform == "darwin":
            store_macos(token)
        elif sys.platform == "win32":
            store_windows(token)
        elif sys.platform.startswith("linux"):
            store_linux(token)
        else:
            raise RuntimeError(
                "Native bootstrap storage is unavailable on this platform; "
                "use host secret injection"
            )
    finally:
        del token
    print("Device-local Proton Pass agent token stored securely.")


def status() -> None:
    if sys.platform == "darwin":
        configured = macos_keychain_token(os.environ.copy()) is not None
    elif sys.platform == "win32":
        configured = windows_credential_token() is not None
    elif sys.platform.startswith("linux"):
        configured = linux_secret_service_token(os.environ.copy()) is not None
    else:
        configured = bool(os.environ.get("PROTON_PASS_PERSONAL_ACCESS_TOKEN"))
    print("configured" if configured else "not configured")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Configure device-local unattended Proton Pass reauthentication."
    )
    parser.add_argument("command", choices=("store", "status"))
    args = parser.parse_args()
    try:
        if args.command == "store":
            store()
        else:
            status()
        return 0
    except (OSError, RuntimeError, subprocess.SubprocessError) as exc:
        print(str(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
