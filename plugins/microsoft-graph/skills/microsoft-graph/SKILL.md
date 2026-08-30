---
name: microsoft-graph
description: Use Microsoft Graph across one or more Microsoft accounts for Outlook, Microsoft 365, Entra, Intune, and other Graph-supported services. Use for Graph authentication, REST requests, mail, calendars, contacts, files, Teams, tasks, users, groups, and related operations.
---

# Microsoft Graph

- Use Microsoft Graph for supported Microsoft cloud data and operations, including Outlook mail, calendars, contacts, OneDrive and SharePoint files, Teams, To Do, Planner, OneNote, Excel, Bookings, users, groups, Entra, Intune, reports, and security data. Check the current Graph documentation when endpoint behavior or coverage matters.
- Do not treat Graph as Azure resource management, Power Platform, or a complete replacement for Exchange, Teams, SharePoint, or Purview administrative PowerShell. Use Graph when it exposes the required capability; otherwise use the appropriate Microsoft service tool.

## Accounts and authentication

- Treat multi-account use as the default design. Every Graph operation must target an explicit Microsoft identity and, when relevant, tenant. Never silently use whichever account authenticated most recently.
- Prefer the account or alias named by the user. If the intended account cannot be determined safely from the request or known non-secret profile metadata, ask which account to use before accessing data or making a change.
- For portable terminal access, prefer the official `Microsoft.Graph.Authentication` PowerShell module version 2.39.0 or later. Its `Connect-MgGraph -LoginHint <ACCOUNT>` flow keeps separate per-account authentication records while Microsoft securely caches and refreshes tokens for the current OS user.
- Before the first request in a process, connect with only the scopes needed for the task, `-LoginHint <ACCOUNT>`, and `-ContextScope CurrentUser`. Then check `Get-MgContext` and confirm that its account and tenant match the intended target. An access check should use `GET /v1.0/me` and stop once identity is confirmed.
- Interactive or brokered sign-in is the normal persistent multi-account path. Device-code authentication is suitable when interactive sign-in is unavailable, but the user must choose the intended identity and the resulting context must be verified; do not assume a login hint selected the device-code account.
- Use delegated authentication for work performed as a person. Use app-only authentication only for an explicitly configured unattended or tenant-wide workflow. Do not create an app registration, client secret, certificate, or broad admin consent merely to avoid an ordinary delegated sign-in.
- Request least-privilege scopes. Add consent only when the requested operation needs it, and distinguish missing consent from an account, tenant, licensing, or service-authorization failure.
- Tokens and refresh material belong only in the official secure local cache or another configured credential provider. Never place them in plugin files, source control, chat, notes, command arguments, logs, or output. The plugin contains no account or authentication state; each device authenticates its own accounts.

## Requests

- Prefer direct structured Graph access over UI automation when Graph supports the task. Use an existing suitable Graph connector, the official Graph PowerShell SDK, a Graph SDK, or REST according to the task; there is no fixed priority among capable direct tools.
- If the selected official Graph runtime is absent or older than required, install or update it in the current user's scope and retry instead of switching to browser automation. For PowerShell, install only `Microsoft.Graph.Authentication` when generic REST access is enough; install additional generated Graph modules only when their typed cmdlets are useful.
- For routine JSON REST calls, prefer `scripts/graph_request.ps1`. It accepts any Graph URI, standard HTTP method, scopes, headers, and JSON body, verifies the selected account, and returns the Graph response. It is an optional transport shortcut, not an operation allowlist. Bypass it for binary transfers, large uploads, batching, subscriptions, specialized SDK behavior, or any task another direct tool handles better.
- Resolve the helper relative to this skill directory. A complete access check is `pwsh -NoProfile -File scripts/graph_request.ps1 -Account <ACCOUNT> -Method GET -Uri '/v1.0/me' -Scopes User.Read`. For other calls, pass the required scopes and optional `-TenantId`, `-Environment`, `-BodyJson`, `-HeadersJson`, or `-OutputFilePath`; do not run a help command first.
- Default to the stable `v1.0` endpoint. Use `beta` only when the required feature is unavailable in `v1.0`, and tell the user when relying on beta behavior.
- Follow `@odata.nextLink` when the complete result set is required. Respect Graph throttling and `Retry-After`; retry only safe operations automatically and do not blindly replay a mutation whose outcome is uncertain.
- For shared or delegated Outlook resources, use the account that holds permission and address the target mailbox or calendar explicitly. Do not mistake a shared mailbox for another authenticated account.
- Before sending mail, changing calendar entries, modifying files, or performing administrative actions, confirm the intended account and target from available context and verify the result after the change.
