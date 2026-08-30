---
name: agent-core
description: Apply foundational operating guidance when working with credentials, accounts, external systems, technical environments, or tasks that can use direct tools instead of a graphical interface.
---

# Agent Core

- Treat credentials as secrets stored in the user's configured password manager or credential provider. Retrieve them only when needed; never store them in source control, plugin files, notes, chat, logs, or command output.
- Use existing secure authentication when available. Pass secrets through supported secure mechanisms instead of displaying or embedding them.
- Prefer direct, structured access such as purpose-built connectors, MCP tools, APIs, CLI commands, and SSH over browser or graphical-interface automation. Use APIs for normal application operations and CLI or SSH for technical system work when available.
- Use the graphical interface when the task is inherently visual or UI-specific, the user requests it, or no suitable direct interface is available.
- Before making changes, confirm the intended account, tenant, project, database, and environment as applicable. Make the smallest appropriate change and verify the result.
