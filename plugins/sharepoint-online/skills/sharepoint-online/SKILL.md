---
name: sharepoint-online
description: Use and administer SharePoint Online across accounts and tenants. Use for sites, lists, document libraries, files, permissions, sharing, OneDrive, site collections, tenant settings, and SharePoint administration; route each operation to Microsoft Graph, the SharePoint Online Management Shell, or PnP PowerShell according to capability and platform.
---

# SharePoint Online

- Use direct structured interfaces rather than browser automation when they can perform the task faithfully. Choose by capability, not a fixed tool order: Microsoft Graph handles many sites, lists, drives, files, and permissions; PnP PowerShell handles broad cross-platform SharePoint operations; Microsoft's SharePoint Online Management Shell remains available on Windows when a required tenant-administration capability is not suitably exposed by Graph or PnP.
- Reuse the Microsoft Graph authentication workflow for Graph-supported SharePoint work. Do not start a separate SharePoint login merely because this skill was selected.

## Administration and authentication

- For SharePoint-native work, use current PnP PowerShell 3 or newer with a tenant-approved Entra application registration. On first use of an account on a device, connect with `Connect-PnPOnline -Url <site-url> -Tenant <tenant> -ClientId <client-id> -DeviceLogin -PersistLogin -ReturnConnection`. Show the Microsoft device-login URL and code, allow completion in any browser or device, and wait for that same attempt to finish.
- Reuse PnP's persisted login on later connections. It stores the refresh authorization in its device-local protected cache and can reuse it across PowerShell sessions and restarts. Do not use `-ForceAuthentication` unless the cached identity is wrong or Microsoft requires interaction, and never use `Disconnect-PnPOnline -ClearPersistedLogin` unless the user explicitly asks to sign out or a verified corrupt cache must be repaired.
- PnP requires a tenant-specific client ID. Reuse an existing approved registration when available; do not silently create an app registration, add permissions, or grant consent. If setup is authorized, request only the permissions appropriate to the intended work. The client ID is configuration, not a secret; authentication tokens remain device-local.
- Treat multiple accounts and tenants as normal. Keep the intended identity, tenant, client ID, admin URL, and target site explicit. Use separate PowerShell processes or returned PnP connection objects when concurrent identities could be ambiguous, and verify the connected site and identity before every mutation.
- Use the current `Microsoft.Online.SharePoint.PowerShell` module on Windows only when a required official tenant-administration cmdlet is unavailable through Graph or PnP. Its delegated login uses an MSAL system browser rather than a persistent device-code flow; do not choose it when the user is remote and an equivalent Graph or PnP operation is available.
- Let the selected official or approved client manage its authentication cache. Do not search a password manager for a Microsoft password or token, and never print, copy, synchronize, or place authentication material in plugin files, projects, cloud-synced folders, source control, chat, or logs.
- Use unattended authentication only when explicitly requested. Prefer managed identity where supported, then certificate-based application authentication; use a credential provider only when a secret is genuinely required.

## Operations

- Let Codex choose suitable commands or requests; this skill is guidance, not an operation allowlist. Use stable Graph endpoints by default, follow pagination when complete results are required, and use focused structured output.
- Confirm the account, tenant, site, library or list, target object, and requested effect before mutations. Inspect current permissions, sharing, retention, locks, quotas, or other governing state when relevant, then verify the observable result without blindly repeating an uncertain mutation.
- Use Microsoft Graph for Microsoft 365 groups, users, and other directory data unless the requested SharePoint operation specifically requires a SharePoint-native interface. Use Exchange Online, Teams, or Azure tooling for administration owned by those services rather than stretching SharePoint tooling beyond its scope.
