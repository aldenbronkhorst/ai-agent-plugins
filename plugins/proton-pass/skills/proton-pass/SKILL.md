---
name: proton-pass
description: Use Proton Pass as a credential provider whenever any service needs stored login details, passwords, API keys, tokens, or other secrets, even when the user names only the destination service. Also use for Proton Pass vault or item access and pass-cli authentication recovery on macOS, Linux, or Windows.
---

Use the bundled managed entrypoint for Proton Pass CLI operations; it resolves `PROTON_PASS_CLI_PATH` before checking `PATH`. Do not decide that the CLI is missing or install another copy based only on a `PATH` lookup.

For routine credential use, do not run a separate session check: the managed entrypoint performs it. Minimize round trips and resolve multiple known `pass://` field references through one managed `pass-cli run` operation when possible.

When a service skill publishes a credential contract, prefer the bundled `scripts/credential_provider_run.py` fast path. It discovers matching active items, ignores trashed items, maps the declared fields, and launches the consumer through one masked `pass-cli run` operation. It does not require service-specific or user-specific configuration. If no compatible item is found or multiple valid active items remain ambiguous, report that non-secret result and fall back or ask for the missing target; do not silently guess.

For that routine contract fast path, resolve bundled paths relative to this skill directory and run `<PYTHON_3_9_PLUS> scripts/credential_provider_run.py --contract <CONTRACT_JSON> [--target <NON_SECRET_HINT>] -- <CONSUMER_COMMAND>`. Use a verified Python 3.9+ runtime already supplied by the host or workspace when available; on Windows do not assume `py -3` exists or mistake a Microsoft Store execution alias for Python. Install a trusted compatible runtime only when none is available. Pass the contract directly without inspecting it first.

If the runner says provider authentication is required and that the consumer was not launched, report the required Proton Pass login and stop; do not scan other connectors, environment files, repositories, or the browser. On Windows, if its dedicated session directory fails with access denied or OS error 183, retry the same managed command once with the host's appropriate allowed filesystem access without inspecting session contents; if it still fails, report the non-secret error and stop.

Read and follow `instructions.yaml` completely before manual vault/item operations, direct CLI use, authentication setup, session-recovery diagnosis, or any workflow other than the routine credential-contract fast path above.
