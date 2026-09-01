---
name: azure-cli
description: Use the official Azure CLI for Azure subscriptions, resource groups, deployments, RBAC, virtual machines, storage, networking, Key Vault, App Service, Functions, AKS, and other Azure resource-management work. Use for Azure authentication and terminal-first operations; use Microsoft Graph instead for Microsoft 365 and Graph-supported identity or collaboration data.
---

# Azure CLI

- Use the current official `az` CLI for Azure resource management. Do not substitute Microsoft Graph, a connector, an MCP server, or browser automation when Azure CLI or Azure Resource Manager can perform the task faithfully.
- If `az` is unavailable, install the current Azure CLI through the platform's trusted package manager. Install Azure CLI extensions or companion tools such as Bicep, `kubectl`, Helm, or AzCopy only when the requested operation actually needs them.

## Accounts and authentication

- Check the existing context with `az account show` before starting another login. If the intended identity is not authenticated, prefer `az login --use-device-code`, adding `--tenant <tenant>` when the target tenant is known. Show the one-time code and Microsoft verification URL, let the user complete sign-in in any browser or device, and wait for that attempt to finish.
- Treat Azure CLI's native MSAL login and token cache as the normal interactive credential path. Do not search a password manager for the user's Microsoft password or an Azure token before trying it. Keep the cache device-local: never inspect, print, copy, synchronize, or place its files in a project, cloud-synced folder, source control, chat, or logs.
- Treat multiple identities, tenants, clouds, and subscriptions as normal. Use `az account list --all` to inspect available contexts, `az account set --subscription <name-or-id>` to select the target, and authenticate the required tenant separately when it is absent. Verify the active user, tenant, cloud, subscription name, and subscription ID before any mutation.
- For unattended work running on Azure, prefer managed identity. Otherwise prefer workload identity federation or a certificate-based service principal over a client secret. Use a secure credential provider only when a secret is genuinely required; never embed it in commands, files, plugin content, output, or source control.

## Operations

- Use Azure CLI command groups for supported operations and `az rest` for Azure Resource Manager capabilities that lack a suitable command. Avoid retrieving or displaying raw access tokens when `az` can make the authenticated request itself.
- Prefer JSON and focused `--query` results for programmatic work. Use the relevant resource IDs, resource groups, locations, and subscription explicitly when context could be ambiguous.
- Inspect current state before changing it. Use deployment or infrastructure `what-if` functionality when it materially clarifies the effect, and verify every mutation afterward. Do not infer authorization for destructive cleanup, broader subscription or tenant changes, or unrelated resources.
- Use Microsoft Graph for Microsoft 365, Outlook, Intune, Entra directory objects, and other Graph-supported data. Use Azure CLI for Azure Resource Manager and Azure service resources; choose the interface that actually owns the requested capability when they overlap.
