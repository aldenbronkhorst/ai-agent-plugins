---
name: proton-pass
description: Use Proton Pass as a credential provider whenever any service needs stored login details, passwords, API keys, tokens, or other secrets, even when the user names only the destination service. Also use for Proton Pass vault or item access and pass-cli authentication recovery on macOS, Linux, or Windows.
---

Use the bundled managed entrypoint for Proton Pass CLI operations; it resolves `PROTON_PASS_CLI_PATH` before checking `PATH`. Do not decide that the CLI is missing or install another copy based only on a `PATH` lookup.

For routine credential use, do not run a separate session check: the managed entrypoint performs it. Minimize round trips and resolve multiple known `pass://` field references through one managed `pass-cli run` operation when possible.

When a service skill publishes a credential contract, prefer the bundled `scripts/credential_provider_run.py` fast path. It discovers matching active items, ignores trashed items, maps the declared fields, and launches the consumer through one masked `pass-cli run` operation. It does not require service-specific or user-specific configuration. If no compatible item is found or multiple valid active items remain ambiguous, report that non-secret result and fall back or ask for the missing target; do not silently guess.

Read and follow `instructions.yaml` completely before every Proton Pass operation.
