---
name: sharepoint-online
description: Use and administer SharePoint Online across accounts and tenants. Use for sites, lists, document libraries, files, permissions, sharing, OneDrive, site collections, tenant settings, and SharePoint administration; route each operation to Microsoft Graph, the SharePoint Online Management Shell, or PnP PowerShell according to capability and platform.
---

# SharePoint Online

- Use direct structured interfaces rather than browser automation when they can perform the task faithfully. Choose by capability, not a fixed tool order: Microsoft Graph handles many sites, lists, drives, files, and permissions; Microsoft's SharePoint Online Management Shell handles organization and site-collection administration; PnP PowerShell is an optional cross-platform community tool for deeper SharePoint operations that the other interfaces do not suitably expose.
- Reuse the Microsoft Graph authentication workflow for Graph-supported SharePoint work. Do not start a separate SharePoint login merely because this skill was selected.

## Administration and authentication

- For official SharePoint tenant administration on Windows, use the current `Microsoft.Online.SharePoint.PowerShell` module and connect to the intended admin URL with modern authentication, normally `Connect-SPOService -Url https://<tenant>-admin.sharepoint.com -UseSystemBrowser $true`. The official module is Windows PowerShell-based; when using PowerShell 7 on Windows, import it with `-UseWindowsPowerShell` when required.
- Treat multiple accounts and tenants as normal. Keep the intended identity, tenant, admin URL, and target site explicit. Because the SharePoint Online Management Shell maintains one service connection per PowerShell session, use separate sessions when concurrent tenants or identities would be ambiguous.
- On macOS, Linux, or when a required site-level capability is unavailable through Graph or the official module, PnP PowerShell may be used. It requires a tenant-specific Entra application registration and client ID. Reuse an existing approved registration when available; do not silently create an app registration, add permissions, or grant consent. If setup is authorized, request only the permissions appropriate to the intended work. Once configured, device-code sign-in is available through `Connect-PnPOnline -DeviceLogin -ClientId <client-id>`.
- Let the selected official or approved client manage interactive authentication. Do not search a password manager for a Microsoft password or token, and never print, copy, synchronize, or place authentication material in plugin files, projects, cloud-synced folders, source control, chat, or logs.
- Use unattended authentication only when explicitly requested. Prefer managed identity where supported, then certificate-based application authentication; use a credential provider only when a secret is genuinely required.

## Operations

- Let Codex choose suitable commands or requests; this skill is guidance, not an operation allowlist. Use stable Graph endpoints by default, follow pagination when complete results are required, and use focused structured output.
- Confirm the account, tenant, site, library or list, target object, and requested effect before mutations. Inspect current permissions, sharing, retention, locks, quotas, or other governing state when relevant, then verify the observable result without blindly repeating an uncertain mutation.
- Use Microsoft Graph for Microsoft 365 groups, users, and other directory data unless the requested SharePoint operation specifically requires a SharePoint-native interface. Use Exchange Online, Teams, or Azure tooling for administration owned by those services rather than stretching SharePoint tooling beyond its scope.
