#!/usr/bin/env python3
"""Discover a service credential and run a consumer with masked secret injection."""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import urllib.parse
from pathlib import Path
from typing import Any, Optional, Sequence

from pass_cli_agent import (
    agent_session_root,
    emit,
    ensure_session,
    is_auth_failure,
    pass_cli_path,
    prepare_environment,
    recover_session,
    redact,
    run_capture,
)


ENVIRONMENT_NAME = re.compile(r"^[A-Z][A-Z0-9_]*$")
CREDENTIAL_VAULT_WORDS = ("agent", "automation", "credential", "secret", "api", "developer")
BUILTIN_FIELDS = {
    "email",
    "username",
    "password",
    "urls",
    "totp_uri",
    "private_key",
    "public_key",
    "ssid",
}


class DiscoveryError(RuntimeError):
    pass


def normalized(value: str) -> str:
    return "".join(character.lower() for character in value if character.isalnum())


def load_contract(path: Path) -> dict[str, Any]:
    try:
        contract = json.loads(path.read_text("utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise DiscoveryError(f"Unable to read credential contract: {exc}") from exc

    service = contract.get("service")
    fields = contract.get("fields")
    if not isinstance(service, dict) or not isinstance(fields, dict) or not fields:
        raise DiscoveryError("Credential contract must define service and fields objects")
    name = service.get("name")
    aliases = service.get("aliases")
    if not isinstance(name, str) or not name or not isinstance(aliases, list) or not aliases:
        raise DiscoveryError("Credential contract service must define a name and aliases")
    for environment_name, specification in fields.items():
        if not isinstance(environment_name, str) or not ENVIRONMENT_NAME.fullmatch(environment_name):
            raise DiscoveryError(f"Invalid environment variable name: {environment_name}")
        if not isinstance(specification, dict) or not isinstance(specification.get("aliases"), list):
            raise DiscoveryError(f"Invalid field specification for {environment_name}")
    return contract


def json_command(
    pass_cli: str,
    arguments: list[str],
    env: dict[str, str],
    session_root: Path,
    injected_token: Optional[str],
    secret_output: bool = False,
) -> Any:
    result = run_capture([pass_cli, *arguments], env, timeout=120)
    if is_auth_failure(result):
        if not recover_session(pass_cli, env, session_root, injected_token):
            raise DiscoveryError("Proton Pass session recovery failed")
        result = run_capture([pass_cli, *arguments], env, timeout=120)
    if result.returncode != 0:
        detail = redact(result.stderr.strip())
        if not secret_output and result.stdout.strip():
            detail = f"{detail}\n{redact(result.stdout.strip())}".strip()
        raise DiscoveryError(detail or "Proton Pass command failed")
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        label = "item details" if secret_output else "command output"
        raise DiscoveryError(f"Proton Pass returned invalid JSON for {label}") from exc


def vault_entries(payload: Any) -> list[dict[str, Any]]:
    values = payload.get("vaults", []) if isinstance(payload, dict) else payload
    if not isinstance(values, list):
        raise DiscoveryError("Unexpected Proton Pass vault-list response")
    return [value for value in values if isinstance(value, dict)]


def item_entries(payload: Any) -> list[dict[str, Any]]:
    values = payload.get("items", []) if isinstance(payload, dict) else payload
    if not isinstance(values, list):
        raise DiscoveryError("Unexpected Proton Pass item-list response")
    return [value for value in values if isinstance(value, dict)]


def item_title(item: dict[str, Any]) -> str:
    title = item.get("title")
    if isinstance(title, str):
        return title
    content = item.get("content")
    if isinstance(content, dict) and isinstance(content.get("title"), str):
        return content["title"]
    return ""


def item_is_active(item: dict[str, Any]) -> bool:
    state = item.get("state", "active")
    return normalized(str(state)) == "active"


def service_matches(title: str, aliases: list[str]) -> bool:
    title_key = normalized(title)
    return any(normalized(alias) in title_key for alias in aliases if normalized(alias))


def add_named_fields(value: Any, output: list[str], section: Optional[str] = None) -> None:
    if isinstance(value, list):
        for child in value:
            add_named_fields(child, output, section)
        return
    if not isinstance(value, dict):
        return

    next_section = section
    section_name = value.get("section_name")
    if isinstance(section_name, str) and section_name:
        next_section = section_name

    name = value.get("name")
    if isinstance(name, str) and name and "content" in value:
        output.append(f"{next_section}.{name}" if next_section else name)

    for key, child in value.items():
        if key in BUILTIN_FIELDS and child not in (None, "", [], {}):
            output.append(key)
        add_named_fields(child, output, next_section)


def extract_item_field_names(payload: Any) -> list[str]:
    if not isinstance(payload, dict):
        raise DiscoveryError("Unexpected Proton Pass item-view response")
    item = payload.get("item", payload)
    if not isinstance(item, dict):
        raise DiscoveryError("Unexpected Proton Pass item-view response")
    fields: list[str] = []
    add_named_fields(item.get("content", item), fields)
    return list(dict.fromkeys(fields))


def choose_field(available: list[str], aliases: list[str]) -> Optional[str]:
    for alias in aliases:
        alias_key = normalized(alias)
        exact = [field for field in available if normalized(field) == alias_key]
        if len(exact) == 1:
            return exact[0]
        unqualified = [
            field
            for field in available
            if normalized(field.rsplit(".", 1)[-1]) == alias_key
        ]
        if len(unqualified) == 1:
            return unqualified[0]
    return None


def map_contract_fields(contract: dict[str, Any], available: list[str]) -> Optional[dict[str, str]]:
    mapped: dict[str, str] = {}
    for environment_name, specification in contract["fields"].items():
        field = choose_field(available, specification["aliases"])
        if field:
            mapped[environment_name] = field
        elif specification.get("required", True):
            return None
    return mapped


def vault_rank(vault: dict[str, Any], aliases: list[str]) -> tuple[int, str]:
    name = str(vault.get("name", ""))
    name_key = normalized(name)
    score = sum(100 for alias in aliases if normalized(alias) in name_key)
    score += sum(10 for word in CREDENTIAL_VAULT_WORDS if normalized(word) in name_key)
    return (-score, name_key)


def candidate_score(candidate: dict[str, Any], aliases: list[str], target: Optional[str]) -> int:
    title_key = normalized(candidate["title"])
    score = 20 if "api" in title_key else 0
    for alias in aliases:
        alias_key = normalized(alias)
        if title_key == alias_key:
            score += 100
        elif title_key.startswith(alias_key):
            score += 75
        elif alias_key in title_key:
            score += 50
    if target:
        target_key = normalized(target)
        combined = normalized(f"{candidate['vault_name']} {candidate['title']}")
        if target_key not in combined:
            return -1
        score += 1000
    return score


def pass_reference(share_id: str, item_id: str, field_name: str) -> str:
    return "pass://{}/{}/{}".format(
        urllib.parse.quote(share_id, safe=""),
        urllib.parse.quote(item_id, safe=""),
        urllib.parse.quote(field_name, safe=""),
    )


def discover_candidate(
    pass_cli: str,
    env: dict[str, str],
    session_root: Path,
    injected_token: Optional[str],
    contract: dict[str, Any],
    target: Optional[str],
) -> dict[str, Any]:
    service = contract["service"]
    aliases = [str(alias) for alias in service["aliases"]]
    vaults = vault_entries(
        json_command(pass_cli, ["vault", "list", "--output", "json"], env, session_root, injected_token)
    )
    title_candidates: list[dict[str, Any]] = []
    for vault in sorted(vaults, key=lambda entry: vault_rank(entry, aliases)):
        share_id = str(vault.get("share_id", ""))
        if not share_id:
            continue
        items = item_entries(
            json_command(
                pass_cli,
                [
                    "item",
                    "list",
                    "--share-id",
                    share_id,
                    "--filter-state",
                    "active",
                    "--output",
                    "json",
                ],
                env,
                session_root,
                injected_token,
            )
        )
        for item in items:
            title = item_title(item)
            if not item_is_active(item) or not service_matches(title, aliases):
                continue
            item_id = str(item.get("id") or item.get("item_id") or "")
            item_share_id = str(item.get("share_id") or share_id)
            if item_id and item_share_id:
                title_candidates.append(
                    {
                        "vault_name": str(vault.get("name", "")),
                        "title": title,
                        "share_id": item_share_id,
                        "item_id": item_id,
                    }
                )

    complete: list[dict[str, Any]] = []
    env["PROTON_PASS_AGENT_REASON"] = (
        f"Supply stored {service['name']} credentials to the requested service client."
    )
    for candidate in title_candidates:
        details = json_command(
            pass_cli,
            [
                "item",
                "view",
                "--share-id",
                candidate["share_id"],
                "--item-id",
                candidate["item_id"],
                "--output",
                "json",
            ],
            env,
            session_root,
            injected_token,
            secret_output=True,
        )
        mapped = map_contract_fields(contract, extract_item_field_names(details))
        if mapped is not None:
            candidate["fields"] = mapped
            candidate["score"] = candidate_score(candidate, aliases, target)
            if candidate["score"] >= 0:
                complete.append(candidate)

    if not complete:
        target_text = f" for target '{target}'" if target else ""
        raise DiscoveryError(
            f"No active Proton Pass item matched {service['name']}{target_text} and its required fields."
        )
    best_score = max(candidate["score"] for candidate in complete)
    best = [candidate for candidate in complete if candidate["score"] == best_score]
    if len(best) != 1:
        labels = ", ".join(
            f"{candidate['vault_name']}/{candidate['title']}" for candidate in best
        )
        raise DiscoveryError(
            f"Multiple active Proton Pass items match {service['name']}: {labels}. "
            "Provide a non-secret --target hint."
        )
    return best[0]


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(
        description="Discover a credential from a public service contract and run its consumer."
    )
    result.add_argument("--contract", type=Path, required=True)
    result.add_argument("--target", help="Non-secret environment or account hint")
    result.add_argument("command", nargs=argparse.REMAINDER)
    return result


def main(argv: Optional[Sequence[str]] = None) -> int:
    args = parser().parse_args(argv)
    command = list(args.command)
    if command and command[0] == "--":
        command = command[1:]
    if not command:
        print("A consumer command is required after --.", file=sys.stderr)
        return 2

    injected_token = os.environ.pop("PROTON_PASS_PERSONAL_ACCESS_TOKEN", None)
    try:
        contract = load_contract(args.contract)
        pass_cli = pass_cli_path()
        session_root = agent_session_root()
        env = prepare_environment(session_root)
        if not ensure_session(pass_cli, env, session_root, injected_token):
            return 1
        candidate = discover_candidate(
            pass_cli,
            env,
            session_root,
            injected_token,
            contract,
            args.target,
        )
        run_env = env.copy()
        for environment_name, field_name in candidate["fields"].items():
            run_env[environment_name] = pass_reference(
                candidate["share_id"], candidate["item_id"], field_name
            )
        result = run_capture([pass_cli, "run", "--", *command], run_env, timeout=180)
        if is_auth_failure(result):
            if not recover_session(pass_cli, run_env, session_root, injected_token):
                return result.returncode or 1
            result = run_capture([pass_cli, "run", "--", *command], run_env, timeout=180)
        emit(result)
        return result.returncode
    except (DiscoveryError, OSError, RuntimeError) as exc:
        print(redact(str(exc)), file=sys.stderr)
        return 1
    finally:
        if injected_token is not None:
            del injected_token


if __name__ == "__main__":
    raise SystemExit(main())
