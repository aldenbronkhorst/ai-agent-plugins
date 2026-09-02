---
name: sharepoint-online
description: Use and administer SharePoint Online across accounts and tenants with Microsoft-provided tools. Use for sites, lists, document libraries, files, permissions, sharing, OneDrive, site collections, tenant settings, and SharePoint administration; route each operation to Microsoft Graph or the SharePoint Online Management Shell according to capability and platform.
---

# SharePoint Online

- Use only Microsoft-provided interfaces by default. Do not require PnP PowerShell, a custom Entra application, or a third-party SharePoint client.
- Use direct structured interfaces rather than browser automation when they can perform the task faithfully. Choose by capability, not a fixed tool order: Microsoft Graph handles sites, lists, drives, files, permissions, and supported tenant settings; Microsoft's SharePoint Online Management Shell handles SharePoint administration that Graph does not expose.
- If the suitable current Microsoft module is missing, install it from Microsoft's trusted publisher rather than switching to an inferior interface solely because it is unavailable locally.
- Reuse the Microsoft Graph authentication workflow for Graph-supported SharePoint work. Do not start a separate SharePoint login merely because this skill was selected.

## Administration and authentication

- Microsoft Graph provides the link-and-code authentication and persistent account reuse for Graph-supported SharePoint work. Use the existing Graph account and consent rather than creating another SharePoint identity.
- When Graph lacks a required administration capability, use the current official `Microsoft.Online.SharePoint.PowerShell` module on Windows. In PowerShell 7, import it with `-UseWindowsPowerShell` when required, then connect to the intended admin URL with `Connect-SPOService -Url https://<tenant>-admin.sharepoint.com -UseSystemBrowser $true`.
- Do not claim that the official SharePoint Online Management Shell supports delegated device-code authentication or persistent cross-session login: its supported delegated MSAL path uses the system browser. Keep the same PowerShell process alive for related commands so it does not prompt again during that work.
- Treat multiple accounts and tenants as normal. Keep the intended identity, tenant, admin URL, and target site explicit. The SharePoint Online Management Shell maintains one service connection per PowerShell session, so use separate processes when concurrent identities would be ambiguous and verify the active tenant before every mutation.
- Let Microsoft tooling manage authentication. Do not search a password manager for a Microsoft password or token, and never print, copy, synchronize, or place authentication material in plugin files, projects, cloud-synced folders, source control, chat, or logs.
- Use unattended authentication only when explicitly requested. Managed identity or certificate authentication may require tenant configuration; do not create an Entra application, add permissions, or grant consent without explicit authorization.

## Operations

- Let Codex choose suitable commands or requests; this skill is guidance, not an operation allowlist. Use stable Graph endpoints by default, follow pagination when complete results are required, and use focused structured output.
- Confirm the account, tenant, site, library or list, target object, and requested effect before mutations. Inspect current permissions, sharing, retention, locks, quotas, or other governing state when relevant, then verify the observable result without blindly repeating an uncertain mutation.
- Use Microsoft Graph for Microsoft 365 groups, users, and other directory data unless the requested SharePoint operation specifically requires the SharePoint Online Management Shell. Use Exchange Online, Teams, or Azure tooling for administration owned by those services rather than stretching SharePoint tooling beyond its scope.
