---
name: microsoft-graph
description: Use Microsoft Graph across one or more Microsoft accounts for Outlook, Microsoft 365, Entra, Intune, and other Graph-supported services. Use for Graph authentication, REST requests, mail, calendars, contacts, files, Teams, tasks, users, groups, and related operations.
---

# Microsoft Graph

- Use Microsoft Graph for supported Microsoft cloud work, including Outlook, Microsoft 365, Entra, Intune, files, collaboration, reports, and security. Graph is not Azure resource management and does not replace service-specific administration where Graph lacks the capability.

## Accounts and authentication

- Use the current official Microsoft Graph PowerShell SDK in PowerShell 7, with `Microsoft.Graph.Authentication` 2.37.0 or newer. If it is absent or older, install or update it for the current user.
- For delegated device-code sign-in, run `scripts/connect_graph.ps1` with the intended account, tenant, environment, and scopes. Keep the helper and the following Graph cmdlets or `Invoke-MgGraphRequest` calls in the same PowerShell process. The helper only acquires and securely caches a token, then connects the ordinary Graph PowerShell SDK; it does not limit which Graph operations Codex can perform.
- Use the helper instead of bare `Connect-MgGraph` or `Connect-MgGraph -UseDeviceCode` for this workflow. On Windows, bare sign-in selects WAM. Current Graph PowerShell device-code releases can also perform a normal token request followed by a second CAE request, causing a second code and a 120-second timeout after the first code succeeds. The helper makes one CAE-enabled acquisition with the official Microsoft libraries already included in the module. Do not add `-LoginHint` to device-code authentication.
- Treat multi-account use as normal. Target an explicit account and tenant, and never assume the most recently authenticated identity is correct. The helper keeps account-selection records separate while tokens remain in the operating system's protected cache.
- On first use of an account on each device, show one device code and let that process finish. Consider sign-in complete only after the helper returns and a simple `GET /v1.0/me` identifies the intended account. Reuse the helper's silent refresh on later requests. If authentication produces another code or a concrete error, stop and diagnose that exact attempt instead of starting more sign-ins.
- When the user wants broad account setup, request in that first consent the broadest practical set of compatible delegated permissions Microsoft accepts for that account and tenant, including Outlook, shared mailboxes, files, collaboration, directory, Intune, security, and compliance where available. Warn once that this is intentionally broad and may require administrator approval. Do not literally combine every published permission, application permission, redundant scope, or account-incompatible scope into one oversized request. Add another consent only when Microsoft could not include a later-required delegated permission in the original consent.
- Use delegated authentication for work performed as a person. App-only authentication is a separate setup for explicitly unattended or tenant-wide work.
- Never expose, print, persist manually, or place tokens and refresh material in plugin files, source control, chat, notes, command arguments, or logs. Each device authenticates its own accounts through Microsoft's supported cache.

## Requests

- Prefer direct structured Graph access over UI automation when Graph supports the task. Let the AI choose the suitable official PowerShell cmdlet or Graph request for the operation; this skill is guidance, not an operation allowlist.
- Default to the stable `v1.0` endpoint. Use `beta` only when the required feature is unavailable in `v1.0`, and tell the user when relying on beta behavior.
- Follow `@odata.nextLink` when the complete result set is required. Respect Graph throttling and `Retry-After`; retry only safe operations automatically and do not blindly replay a mutation whose outcome is uncertain.
- For shared or delegated Outlook resources, use the account that holds permission and address the target mailbox or calendar explicitly. Do not mistake a shared mailbox for another authenticated account.
- Before sending mail, changing calendar entries, modifying files, or performing administrative actions, confirm the intended account and target from available context and verify the result after the change.
