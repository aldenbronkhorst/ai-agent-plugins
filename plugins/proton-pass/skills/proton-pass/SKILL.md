---
name: proton-pass
description: Use Proton Pass as a credential provider whenever any service needs stored login details, passwords, API keys, tokens, or other secrets, even when the user names only the destination service. Also use for Proton Pass vault or item access and pass-cli authentication recovery on macOS, Linux, or Windows.
---

Use the bundled managed entrypoint for Proton Pass CLI operations; it resolves `PROTON_PASS_CLI_PATH` before checking `PATH`. Do not decide that the CLI is missing or install another copy based only on a `PATH` lookup.

For routine credential use, do not run a separate session check: the managed entrypoint performs it. Minimize round trips and resolve multiple known `pass://` field references through one managed `pass-cli run` operation when possible.

Read and follow `instructions.yaml` completely before every Proton Pass operation.
