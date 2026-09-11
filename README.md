# AI Agent Plugins

Reusable [Agent Skills](https://agentskills.io/specification) for AI agents.
Each capability lives in one standard `skills/<name>/` directory containing
`SKILL.md` and its supporting scripts and references. Every compatible agent
uses the same files and installation route.

## Install

Use the open [skills CLI](https://github.com/vercel-labs/skills) with Node.js
and npm available:

```bash
npx skills add aldenbronkhorst/ai-agent-plugins
```

Choose the skills, supported agents, and installation scope when prompted.
The installer handles destination directories. Its supported agents include
Claude Code, Hermes, Codex, Cursor, OpenCode, and others. In non-interactive
agent environments, the installer may select the current agent automatically;
run it interactively when choosing additional apps.

To inspect the available skills without installing, or select particular skills:

```bash
npx skills add aldenbronkhorst/ai-agent-plugins --list
npx skills add aldenbronkhorst/ai-agent-plugins --skill agent-core github-cli
```

For another Agent Skills-compatible loader, import a **whole skill directory**
from `skills/<name>/`, including scripts and supporting files. Copying only
`SKILL.md` loses the helpers. Use the loader's supported import mechanism,
then refresh its skills or start a new session.

If you previously installed a marketplace version, remove that copy through
your app's plugin manager and install the shared skills using the command
above. This repository now distributes skills directly; the previous
marketplace installation route is retired. Use one installation route per
skill in an app to avoid loading it twice.

## Skills

| Skill | Capability | Runtime requirements |
| --- | --- | --- |
| `agent-core` | Credential handling, direct tool use, dependency setup, target verification. | Uses the tools available in the host. |
| `github-cli` | GitHub repositories, issues, pull requests, Actions, and accounts. | GitHub CLI (`gh`) and Git. |
| `azure-cli` | Azure resource management with account and subscription contexts. | Azure CLI (`az`). |
| `microsoft-graph` | Microsoft 365, Outlook, Entra, Intune, and other Graph services. | PowerShell 7.2+ and Microsoft Graph PowerShell. |
| `exchange-online` | Exchange administration and persistent device-code authentication. | PowerShell 7, ExchangeOnlineManagement, and Azure CLI. |
| `sharepoint-online` | SharePoint and OneDrive operations and administration. | Microsoft Graph; Windows and Microsoft's SharePoint management module for operations requiring that shell. |
| `odoo-19` | Odoo development, deployment, and external API operations. | Python 3.9+ for the bundled API helper. |
| `proton-pass` | Credential access and automatic CLI session recovery. | Python 3.9+, Proton Pass CLI, and device-local secure authentication. |

The shared format makes instructions discoverable and reusable. The host
still needs command execution, access to the installed resources, and access
to the relevant service. CLI dependencies and authentication are separate
from skill installation; a chat-only app cannot execute the helpers.

## Device setup

Authentication remains local to each device. Skill files contain no
credentials or tokens. Microsoft-service skills treat multiple accounts and
tenants as a baseline: the agent selects and verifies the intended identity
instead of relying on the most recently authenticated session.

### Microsoft Graph

Install PowerShell 7 and the current official Microsoft Graph PowerShell
modules (`Microsoft.Graph.Authentication` 2.37.0 or newer). Each device signs
in to its own accounts with Microsoft's supported device-code flow and keeps
its authentication cache in device-local secure storage.

### Exchange and SharePoint

Exchange uses Azure CLI's device-code login as a persistent identity broker,
then passes a short-lived token in memory to the official Exchange module. No
Azure subscription is required. SharePoint reuses Graph where possible and
uses Microsoft's SharePoint Online Management Shell for administration that
Graph does not expose. Graph provides persistent device-code authentication;
the official SharePoint shell uses its supported system-browser login instead.

### Proton Pass

Install `pass-cli` using the [official installation instructions](https://protonpass.github.io/pass-cli/get-started/installation/)
for macOS, Linux, or Windows. The wrapper maintains an isolated agent session,
checks it before every command, and performs one verified recovery when
authentication expires. For unattended recovery, use native secure storage
on the device or inject a minimally scoped Personal Access Token through
`PROTON_PASS_PERSONAL_ACCESS_TOKEN`. The bundled bootstrap helper supports
macOS Keychain, Windows Credential Manager, and Linux Secret Service.

## Maintain the shared skills

- Keep instructions in standard `SKILL.md` files with `name` and `description`
  frontmatter. Use the [Agent Skills specification](https://agentskills.io/specification)
  for optional fields.
- Keep scripts and references inside their skill directory, and resolve their
  paths relative to that directory. Do not depend on an app's cache layout or
  the user's current working directory.
- Use ordinary CLIs, service APIs, and portable runtimes. Describe real runtime
  requirements without adding AI-app-specific tool names, manifests, hooks,
  prompts, adapters, or configuration files.
- Keep authentication device-local and outside the skill. Resolve companion
  skills by their capability/name through the host's discovery mechanism.

Validate the shared format and installer discovery before publishing. In an
activated Python environment:

```bash
python -m pip install skills-ref==0.1.1
agentskills validate skills/proton-pass
npx skills add . --list
```

The GitHub workflow validates every skill with the Agent Skills reference
validator and checks discovery with the general installer. These checks cover
format and packaging; they do not claim every workflow was tested in every app.

## Updates

Edit the shared skill once, validate it, then commit and push the change.
Users who installed through the general installer can check and apply updates:

```bash
npx skills check
npx skills update
```

Refresh the host's skills or start a new session after updating.
