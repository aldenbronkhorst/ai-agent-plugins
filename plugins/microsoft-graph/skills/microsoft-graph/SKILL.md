---
name: microsoft-graph
description: Use Microsoft Graph across one or more Microsoft accounts for Outlook, Microsoft 365, Entra, Intune, and other Graph-supported services. Use for Graph authentication, REST requests, mail, calendars, contacts, files, Teams, tasks, users, groups, and related operations.
---

# Microsoft Graph

- Use Microsoft Graph for supported Microsoft cloud work, including Outlook, Microsoft 365, Entra, Intune, files, collaboration, reports, and security. Graph is not Azure resource management and does not replace service-specific administration where Graph lacks the capability.

## Accounts and authentication

- Use the current official Microsoft Graph PowerShell SDK in PowerShell 7 for terminal access, with `Microsoft.Graph.Authentication` 2.37.0 or newer. If it is absent or older, install or update the required modules for the current user. Use `Connect-MgGraph -UseDeviceCode` for sign-in and Graph cmdlets or `Invoke-MgGraphRequest` for operations. Do not introduce a custom authentication runtime.
- On Windows, do not use bare `Connect-MgGraph` for this workflow because its default interactive route uses WAM. Pass `-UseDeviceCode` explicitly so the supported device-code flow is selected. Do not downgrade below 2.37.0: Microsoft fixed the device-code token-cache problem in 2.37.0 and has announced future delegated-authentication restrictions for versions before 2.36.1.
- Treat multi-account use as normal. Target an explicit account and tenant, verify `Get-MgContext`, and never assume the most recently authenticated identity is correct. Use separate PowerShell session contexts when accounts must remain active independently; let Microsoft's SDK manage its token cache.
- On first use of an account, show the device code once and let that same `Connect-MgGraph` process finish. Browser success is only consent confirmation: consider sign-in complete only after that command returns, `Get-MgContext` identifies the intended account, and a simple `GET /v1.0/me` succeeds in the same PowerShell process. Do not keep issuing codes after a concrete failure; diagnose the exact current-SDK error first. Reuse the authenticated context and its refresh behavior on later requests.
- When the user wants broad account setup, request in that first consent the broadest practical set of compatible delegated permissions Microsoft accepts for that account and tenant, including Outlook, shared mailboxes, files, collaboration, directory, Intune, security, and compliance where available. Warn once that this is intentionally broad and may require administrator approval. Do not literally combine every published permission, application permission, redundant scope, or account-incompatible scope into one oversized request. Add another consent only when Microsoft could not include a later-required delegated permission in the original consent.
- Use delegated authentication for work performed as a person. App-only authentication is a separate setup for explicitly unattended or tenant-wide work.
- Never expose, print, persist manually, or place tokens and refresh material in plugin files, source control, chat, notes, command arguments, or logs. Each device authenticates its own accounts through Microsoft's supported cache.

## Requests

- Prefer direct structured Graph access over UI automation when Graph supports the task. Let the AI choose the suitable official PowerShell cmdlet or Graph request for the operation; this skill is guidance, not an operation allowlist.
- Default to the stable `v1.0` endpoint. Use `beta` only when the required feature is unavailable in `v1.0`, and tell the user when relying on beta behavior.
- Follow `@odata.nextLink` when the complete result set is required. Respect Graph throttling and `Retry-After`; retry only safe operations automatically and do not blindly replay a mutation whose outcome is uncertain.
- For shared or delegated Outlook resources, use the account that holds permission and address the target mailbox or calendar explicitly. Do not mistake a shared mailbox for another authenticated account.
- Before sending mail, changing calendar entries, modifying files, or performing administrative actions, confirm the intended account and target from available context and verify the result after the change.
