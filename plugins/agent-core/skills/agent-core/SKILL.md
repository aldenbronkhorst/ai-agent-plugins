---
name: agent-core
description: Apply foundational operating guidance when working with credentials, accounts, external systems, technical environments, or tasks that can use direct tools instead of a graphical interface, including discovery of installed credential providers.
---

# Agent Core

- Treat credentials as secrets stored in the user's configured credential provider, such as a password manager. Retrieve them only when needed; never store them in source control, plugin files, notes, chat, logs, or command output.
- Use existing secure authentication when available. Pass secrets through supported secure mechanisms instead of displaying or embedding them.
- When authentication is needed, identify and use an available credential-provider tool or skill. Do this before reporting that access is unavailable or asking the user to supply credentials.
- Choose the best available access method for the task; purpose-built connectors, MCP tools, APIs, CLI commands, and SSH are options, not a fixed priority order. Prefer direct, structured access over graphical-interface automation only when it is suitable for the task, considering capability, reliability, security, and fidelity.
- If the best in-scope approach requires a missing tool or library, install a trusted, compatible version through the project's existing package manager or an isolated environment instead of silently switching to an inferior workaround.
- Prefer project-local or temporary installs. Ask first only when installation requires administrator privileges, changes shared or production state, creates material cost, or has unclear trust or risk; otherwise install, verify, and continue.
- Use the graphical interface when the task is inherently visual or UI-specific, the user requests it, or no suitable direct interface is available.
- Before making changes, confirm the intended account, tenant, project, database, and environment as applicable. Make the smallest appropriate change and verify the result.
