---
name: proton-pass
description: Use Proton Pass as a credential provider whenever any service needs stored login details, passwords, API keys, tokens, or other secrets, even when the user names only the destination service. Also use for Proton Pass vault or item access and pass-cli authentication recovery on macOS, Linux, or Windows.
---

Use the bundled managed entrypoint for Proton Pass CLI operations; it resolves `PROTON_PASS_CLI_PATH` before checking `PATH`. Do not decide that the CLI is missing or install another copy based only on a `PATH` lookup.

For routine credential use, do not run a separate session check: the managed entrypoint performs it and automatically repairs an expired session from this device's securely stored agent token. It uses macOS Keychain, Windows Credential Manager, Linux Secret Service when available, or secure host injection. Minimize round trips and resolve multiple known `pass://` field references through one managed `pass-cli run` operation when possible.

Keep the two lifetimes distinct: a Proton agent token may be issued for up to one year, while each CLI session created from it lasts two hours. An expired CLI session normally requires automatic reauthentication with the same current agent token, not a new token.

If a device has not yet stored its agent token, or Proton rejects the stored token while creating a new CLI session, use the bundled `scripts/proton_pass_bootstrap.py store` helper with the currently issued scoped Proton Pass agent token where native secure storage is available; use the host's secure secret injection otherwise. This is device-local setup, not ordinary session reauthentication. Never move a bootstrap token or session from another computer, and do not substitute browser automation for the managed recovery flow.

When a service skill publishes a credential contract, prefer the bundled `scripts/credential_provider_run.py` fast path. It discovers matching active items, ignores trashed items, maps the declared fields, and launches the consumer through one masked `pass-cli run` operation. It does not require service-specific or user-specific configuration. If no compatible item is found or multiple valid active items remain ambiguous, report that non-secret result and fall back or ask for the missing target; do not silently guess.

For that routine contract fast path, resolve bundled paths relative to this skill directory and run `<PYTHON_3_9_PLUS> scripts/credential_provider_run.py --contract <CONTRACT_JSON> [--target <NON_SECRET_HINT>] -- <CONSUMER_COMMAND>`. Use a verified Python 3.9+ runtime already supplied by the host or workspace when available; on Windows do not assume `py -3` exists or mistake a Microsoft Store execution alias for Python. Install a trusted compatible runtime only when none is available. Pass the contract directly without inspecting it first.

If automatic recovery fails, distinguish a missing or Proton-rejected device agent token from an ordinary two-hour session expiry and report the wrapper's non-secret error. Do not scan other connectors, environment files, repositories, another computer, or the browser.

Read and follow `instructions.yaml` completely before manual vault/item operations, direct CLI use, authentication setup, session-recovery diagnosis, or any workflow other than the routine credential-contract fast path above.
