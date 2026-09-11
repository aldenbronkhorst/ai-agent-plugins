# AI Agent Plugins

Reusable [Agent Skills](https://agentskills.io/specification) for AI agents.
Each capability is one standard `SKILL.md` folder with its supporting scripts
and references. The same files are used by every compatible agent; there are
no separate implementations, prompts, or adapters for individual AI apps.

## Install with the general skills installer

Use the open [skills CLI](https://github.com/vercel-labs/skills) with Node.js
and npm available:

```bash
npx skills add aldenbronkhorst/ai-agent-plugins
```

Choose the skills, supported agents, and installation scope when prompted.
The installer handles the destination directories; this repository does not
maintain application-specific path mappings. Its supported agents include
Claude Code, Hermes, Codex, Cursor, OpenCode, and others. In non-interactive
agent environments, the installer may select the current agent automatically;
run it interactively when choosing additional apps.

To inspect the available skills without installing, or select particular skills:

```bash
npx skills add aldenbronkhorst/ai-agent-plugins --list
npx skills add aldenbronkhorst/ai-agent-plugins --skill agent-core github-cli
```

For another Agent Skills-compatible loader, import a **whole skill directory**
from `plugins/<name>/skills/<name>/`, including scripts and supporting files.
Copying only `SKILL.md` loses the helpers. Use that app's supported import or
skill-directory mechanism, then refresh its skills or start a new session.

### What compatibility means

The shared format makes the instructions discoverable and reusable. The host
still needs permission to run commands, read the installed skill resources,
and reach the relevant service. Installing a skill does not install its CLI
dependencies, transfer credentials, grant permissions, or bypass a host's
sandbox. A chat-only app without local tool execution cannot run these helpers.

| Capability | Runtime and service requirements |
| --- | --- |
| Agent Core | Uses the tools available in the host. |
| GitHub | GitHub CLI (`gh`) and Git. |
| Azure | Azure CLI (`az`). |
| Microsoft Graph | PowerShell 7.2+ and Microsoft Graph PowerShell. |
| Exchange Online | PowerShell 7, ExchangeOnlineManagement, and Azure CLI. |
| SharePoint Online | Microsoft Graph; Windows and Microsoft's SharePoint management module for operations requiring that shell. |
| Odoo 19 | Python 3.9+ for the bundled API helper and access to the intended Odoo service. |
| Proton Pass | Python 3.9+, Proton Pass CLI, and device-local secure authentication. |

Use one installation route per skill in an app to avoid loading it twice.
Existing Codex marketplace installations can continue using the wrapper below.

## Layout

- `plugins/proton-pass/` provides portable Proton Pass CLI access and session
  recovery for agents. It is the first marketplace entry.
- `plugins/odoo-19/` provides minimal, project-neutral Odoo 19 development and
  deployment guidance.
- `plugins/agent-core/` provides foundational guidance for secure credentials,
  direct tool use, appropriate dependency setup, target confirmation, and
  result verification.
- `plugins/microsoft-graph/` provides multi-account Microsoft Graph guidance
  for Outlook and Microsoft 365 through the official PowerShell SDK.
- `plugins/github-cli/` provides terminal-first GitHub access through the
  official GitHub CLI and Git, including multi-account device-code setup.
- `plugins/azure-cli/` provides Azure resource management through the official
  Azure CLI with reusable account and subscription contexts.
- `plugins/exchange-online/` provides Exchange administration through the
  official PowerShell module with persistent device-code authentication.
- `plugins/sharepoint-online/` routes SharePoint work through Microsoft Graph
  or the official management shell according to capability.
- Each `plugins/<name>/skills/<name>/` directory is the portable source of
  truth. The existing `.codex-plugin/` and `.agents/plugins/` files are optional
  marketplace packaging outside the shared skills.

Microsoft-service plugins treat multiple accounts and tenants as a baseline:
the agent selects and verifies the intended identity instead of relying on the
most recently authenticated session. Authentication remains local to each
device.

## Existing Codex marketplace installation

Add the GitHub-backed marketplace:

```bash
codex plugin marketplace add aldenbronkhorst/ai-agent-plugins
```

Install the Proton Pass agent workflow:

```bash
codex plugin add proton-pass@ai-agent-plugins
```

Install the Odoo 19 workflow when needed:

```bash
codex plugin add odoo-19@ai-agent-plugins
```

Install the general operating guidance:

```bash
codex plugin add agent-core@ai-agent-plugins
```

Install the multi-account Microsoft Graph workflow:

```bash
codex plugin add microsoft-graph@ai-agent-plugins
```

Install Exchange or SharePoint administration when needed:

```bash
codex plugin add exchange-online@ai-agent-plugins
codex plugin add sharepoint-online@ai-agent-plugins
```

Install GitHub or Azure access when needed:

```bash
codex plugin add github-cli@ai-agent-plugins
codex plugin add azure-cli@ai-agent-plugins
```

Start a new Codex task after installing so the plugin skill is loaded.

## Microsoft Graph on a new device

Install PowerShell 7 and the current official Microsoft Graph PowerShell
modules (`Microsoft.Graph.Authentication` 2.37.0 or newer). Each device signs
in to its own accounts with Microsoft's supported device-code flow and keeps
its authentication cache in device-local secure storage. Plugin files contain
no credentials or tokens.

## Exchange and SharePoint on a new device

Exchange uses Azure CLI's device-code login as a persistent identity broker,
then passes a short-lived token in memory to the official Exchange module. No
Azure subscription is required. SharePoint reuses Graph where possible and
uses Microsoft's SharePoint Online Management Shell for administration that
Graph does not expose. Graph provides persistent device-code authentication;
the official SharePoint shell uses its supported system-browser login instead.

## Proton Pass on a new device

Install `pass-cli` using the [official installation instructions](https://protonpass.github.io/pass-cli/get-started/installation/)
for macOS, Linux, or Windows. The wrapper maintains an isolated agent session,
checks it before every command, and performs one verified recovery when
authentication expires. For unattended recovery, inject a minimally scoped
Personal Access Token through `PROTON_PASS_PERSONAL_ACCESS_TOKEN`. On macOS,
the wrapper can instead read its generic Keychain entry and can migrate the
former local Codex entry. The plugin never stores the token in its files.

## Maintain the shared skills

- Keep instructions in standard `SKILL.md` files with `name` and `description`
  frontmatter. Use the [Agent Skills specification](https://agentskills.io/specification)
  for optional fields.
- Keep scripts and references inside their skill directory, and resolve their
  paths relative to that directory. Do not depend on an app's cache layout or
  the user's current working directory.
- Use ordinary CLIs, service APIs, and portable runtimes. Describe real runtime
  requirements without adding AI-app-specific tool names, hooks, prompts, or
  configuration files to shared skills.
- Keep authentication device-local and outside the skill. Resolve companion
  skills by their capability/name through the host's discovery mechanism.

Validate the shared format and installer discovery before publishing:

```bash
python -m pip install skills-ref==0.1.1
agentskills validate plugins/proton-pass/skills/proton-pass
npx skills add . --list
```

The GitHub workflow validates every skill with the Agent Skills reference
validator and checks discovery with the general installer. These checks cover
format and packaging; they do not claim every workflow was tested in every app.

### Publish updates

Edit the shared skill once. For the existing Codex wrapper, also refresh the
changed plugin's version in `.codex-plugin/plugin.json` so installed copies
do not reuse the older cache. Then commit and push the change.

Users who installed through the general installer can check and apply updates:

```bash
npx skills check
npx skills update
```

### Update an existing Codex marketplace installation

```bash
codex plugin marketplace upgrade ai-agent-plugins
codex plugin add proton-pass@ai-agent-plugins
codex plugin add odoo-19@ai-agent-plugins
codex plugin add agent-core@ai-agent-plugins
codex plugin add microsoft-graph@ai-agent-plugins
codex plugin add exchange-online@ai-agent-plugins
codex plugin add sharepoint-online@ai-agent-plugins
codex plugin add github-cli@ai-agent-plugins
codex plugin add azure-cli@ai-agent-plugins
```

Start a new task after updating.
