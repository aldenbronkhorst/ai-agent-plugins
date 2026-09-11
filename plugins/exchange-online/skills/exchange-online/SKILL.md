---
name: exchange-online
description: Use the official Exchange Online PowerShell module for Exchange administration across accounts and tenants. Use for mailboxes, shared mailboxes, mailbox permissions, distribution groups, mail flow, connectors, accepted domains, Exchange settings, and Security & Compliance PowerShell; use Microsoft Graph instead for ordinary email and calendar content.
---

# Exchange Online

- Use the current official `ExchangeOnlineManagement` module in PowerShell 7 for Exchange Online administration. If PowerShell 7 or the module is unavailable, install the required current component through the platform's trusted package or PowerShell module tooling. Do not add helpers, alternate clients, or fixed machine paths unless a concrete task requires them.
- Use Exchange Online PowerShell for administrative capabilities such as mailboxes, shared mailboxes, permissions, distribution groups, accepted domains, connectors, transport rules, and organization settings. Use Microsoft Graph for reading, drafting, sending, replying to, or forwarding messages and for ordinary calendar work.

## Accounts and authentication

- Check existing Exchange connections with `Get-ConnectionInformation` before starting another sign-in. Reuse a connection only when its account, tenant, environment, and token status/expiry match the task; a Security & Compliance session is not an Exchange session.
- If a new or refreshed connection is needed, run `scripts/connect_exchange.ps1`, resolved relative to this skill directory, with the intended account and tenant GUID or verified domain. It uses Azure CLI's supported device-code login and persistent MSAL cache, obtains a short-lived Exchange token without displaying it, and connects the ordinary Exchange Online module with `Connect-ExchangeOnline -AccessToken`. An Azure subscription is not required. Set `-ExchangeEnvironmentName` for a sovereign environment; the helper selects its Azure cloud in an isolated profile and supplies the matching Exchange token resource unless `-ExchangeResource` explicitly overrides that audience.
- On first use of an account on a device, show the Azure CLI device-login URL and code and wait for that same attempt to finish. Later invocations should refresh silently from the device-local cache. Start interactive login only when no matching cached account exists or Microsoft requires renewed authorization, with at most one attempt per helper invocation. Network failures, unavailable services, and policy failures need their own diagnosis.
- Invoke the helper and all following Exchange cmdlets in the same PowerShell process. The helper establishes authentication only; it does not wrap, filter, or limit Exchange commands. Do not run it in a short-lived process that exits before the requested work begins.
- Treat multiple accounts and tenants as normal. The helper reuses an existing matching Azure CLI context or isolates additional identities in account-specific local profiles. Use separate PowerShell processes for different identities so imported cmdlets cannot select another connection. Keep the intended identity and organization explicit and verify the active connection, including the returned `ConnectionId`, before every mutation.
- Supplied access tokens do not refresh themselves. Rerun the helper in the same PowerShell process when its Exchange token expires; it silently obtains a fresh token and reconnects when cached authorization remains valid.
- Disconnect the live Exchange session only after all related work in that process is complete. This releases the Exchange connection without intentionally clearing the persistent Azure CLI sign-in. Do not clear the Azure CLI account or its cache unless the user explicitly asks to sign out or a verified corrupt cache must be repaired.
- Let Azure CLI manage its native local authentication cache. It encrypts that cache on Windows; on macOS and Linux it is protected by the local user profile rather than encrypted by Azure CLI. Never inspect, print, copy, synchronize, or place authentication material in plugin files, projects, cloud-synced folders, source control, chat, or logs.
- Use app-only authentication only for explicitly unattended work. Prefer managed identity where supported, then certificate-based authentication; use a credential provider only when a secret is genuinely required.

## Operations

- Let the agent choose the suitable official cmdlet for the task; this skill is guidance, not an operation allowlist. Use structured, focused output and inspect current state before changing it.
- Confirm the organization, account, target object, and requested effect before administrative mutations. Verify the observable result afterward, accounting for normal Exchange propagation delays, and do not blindly repeat a mutation whose outcome is uncertain.
- For Microsoft Purview or Security & Compliance PowerShell tasks supported by this module, use `Connect-IPPSSession` with the intended account and tenant rather than creating a separate generic Microsoft session.
- Never send, reply to, or forward email through an administrative workaround. Route message operations through Microsoft Graph and require its complete preview and explicit-send-confirmation workflow.
