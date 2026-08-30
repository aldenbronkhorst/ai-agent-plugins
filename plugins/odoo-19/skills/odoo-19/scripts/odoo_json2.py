#!/usr/bin/env python3
"""Send one unrestricted Odoo 19 JSON-2 request using injected credentials."""

from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Optional, Sequence


USER_AGENT = "ai-agent-plugins-odoo-json2/0.1"


def json_body(body: Optional[str], body_file: Optional[str]) -> bytes:
    if body_file:
        raw = sys.stdin.read() if body_file == "-" else Path(body_file).read_text("utf-8")
    else:
        raw = body if body is not None else "{}"

    try:
        parsed = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise ValueError(f"Request body is not valid JSON: {exc.msg}") from exc
    if not isinstance(parsed, dict):
        raise ValueError("Odoo JSON-2 requires the request body to be a JSON object")
    return raw.encode("utf-8")


def endpoint(base_url: str, model: str, method: str) -> str:
    root = base_url.strip().rstrip("/")
    if not root:
        raise ValueError("ODOO_URL is empty")
    if root.endswith("/json/2"):
        api_root = root
    else:
        api_root = f"{root}/json/2"
    model_part = urllib.parse.quote(model, safe="._-")
    method_part = urllib.parse.quote(method, safe="._-")
    return f"{api_root}/{model_part}/{method_part}"


def send_request(
    base_url: str,
    api_key: str,
    database: Optional[str],
    model: str,
    method: str,
    body: bytes,
    timeout: float,
) -> bytes:
    headers = {
        "Authorization": f"bearer {api_key}",
        "Content-Type": "application/json; charset=utf-8",
        "User-Agent": USER_AGENT,
    }
    if database:
        headers["X-Odoo-Database"] = database
    request = urllib.request.Request(
        endpoint(base_url, model, method),
        data=body,
        headers=headers,
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return response.read()


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(
        description=(
            "Send an arbitrary Odoo 19 JSON-2 model method call. Credentials are "
            "read only from ODOO_URL, ODOO_API_KEY, and optional ODOO_DATABASE."
        )
    )
    result.add_argument("model", help="Odoo technical model name")
    result.add_argument("method", help="Odoo model method name")
    body_group = result.add_mutually_exclusive_group()
    body_group.add_argument("--body", help="JSON-object request body; defaults to {}")
    body_group.add_argument(
        "--body-file",
        help="Read the JSON-object body from this file, or use - for standard input",
    )
    result.add_argument("--timeout", type=float, default=30.0)
    return result


def main(argv: Optional[Sequence[str]] = None) -> int:
    args = parser().parse_args(argv)
    base_url = os.environ.get("ODOO_URL")
    api_key = os.environ.get("ODOO_API_KEY")
    database = os.environ.get("ODOO_DATABASE") or None
    if not base_url or not api_key:
        print(
            "ODOO_URL and ODOO_API_KEY must be supplied securely in the environment.",
            file=sys.stderr,
        )
        return 2

    try:
        payload = json_body(args.body, args.body_file)
        response = send_request(
            base_url,
            api_key,
            database,
            args.model,
            args.method,
            payload,
            args.timeout,
        )
        sys.stdout.buffer.write(response)
        if response and not response.endswith(b"\n"):
            sys.stdout.buffer.write(b"\n")
        return 0
    except urllib.error.HTTPError as exc:
        response = exc.read()
        if response:
            sys.stdout.buffer.write(response)
            if not response.endswith(b"\n"):
                sys.stdout.buffer.write(b"\n")
        print(f"Odoo JSON-2 request failed with HTTP {exc.code}.", file=sys.stderr)
        return 1
    except (OSError, ValueError, urllib.error.URLError) as exc:
        print(f"Odoo JSON-2 request failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
