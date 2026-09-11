# AI Agent Plugins

Portable plugins containing Agent Skills and their helper scripts. Install through
an application's plugin manager to retain its Git source and update lifecycle.

## Install in Hermes

In **Capabilities → Plugins → Install from Git**, enter:

```text
https://github.com/aldenbronkhorst/ai-agent-plugins
```

Install and enable **ai-agent-plugins**. This is one portable agent plugin with
all eight workflows and their helper scripts. It does not add desktop UI code.
Start a new session after installation (restart the gateway if Hermes requests it).

The equivalent CLI command is:

```bash
hermes plugins install aldenbronkhorst/ai-agent-plugins --enable
```

Hermes' Git installer inspects the selected directory for a root `plugin.json`;
it does not import the multi-plugin Codex or Claude marketplace catalog. The
repository therefore also ships a complete portable package at its root.
Use the repository root in Hermes: the tested installer keeps its `.git`
directory, which is required by the native updater. Subdirectory installs in
that Hermes version lose the Git checkout and cannot use that updater.

Update through Hermes' plugin controls, or:

```bash
hermes plugins update ai-agent-plugins
```

This preserves native Git updates. A background automatic update schedule has
not been verified; pushing to GitHub does not by itself make Hermes reload it.

## Install in Codex

Add this repository using the app's **Add marketplace** function, or:

```bash
codex plugin marketplace add aldenbronkhorst/ai-agent-plugins
codex plugin add proton-pass@ai-agent-plugins
```

The marketplace offers the eight plugins individually, with their original
icons. Replace `proton-pass` with another name from the table below. Start a new
task after installation. To refresh and apply an update:

```bash
codex plugin marketplace upgrade ai-agent-plugins
codex plugin add proton-pass@ai-agent-plugins
```

## Install in Claude Code

Use the native plugin marketplace:

```text
/plugin marketplace add aldenbronkhorst/ai-agent-plugins
/plugin install proton-pass@ai-agent-plugins
```

To enable automatic marketplace updates, open `/plugin`, choose **Marketplaces**,
select **ai-agent-plugins**, and enable auto-update. Third-party marketplaces do
not enable it by default. Reload plugins or start a new session when prompted.

## Included plugins

| Plugin | Purpose |
| --- | --- |
| `proton-pass` | Credential retrieval and session recovery using Proton Pass. |
| `odoo-19` | Odoo 19 development, deployment, and operations. |
| `agent-core` | Credential handling, tool selection, and result verification. |
| `microsoft-graph` | Microsoft 365 and Entra through Microsoft Graph. |
| `github-cli` | GitHub through the official CLI and Git. |
| `azure-cli` | Azure subscriptions and resources through the official CLI. |
| `exchange-online` | Exchange administration through official PowerShell tools. |
| `sharepoint-online` | SharePoint through Graph and the official management shell. |

## Source and generated packages

Author each plugin in `plugins/<name>/`:

- `plugin.json`: [Agent Plugins v1](https://agent-plugins.org/plugin-authors/manifest)
  manifest and optional namespaced presentation metadata.
- `skills/<name>/`: canonical skill instructions, scripts, tests, and resources.
- `assets/`: plugin icons.

The root `plugin.json` identifies the all-in-one portable package. Its `skills/`
directory is a generated copy of the individual plugins' skills, including all
helpers and executable permissions. Copies are committed because Git installers
need a complete package without running a build. There are no cross-package
symlinks.

The build also generates small `.codex-plugin/plugin.json` and
`.claude-plugin/plugin.json` compatibility manifests and the Claude marketplace
catalog. The original `.agents/plugins/marketplace.json` retains the Codex
catalog order, availability policies, and display name. These are packaging and
presentation metadata; the workflow instructions and helper code are shared.

After editing canonical content:

```bash
python3 scripts/build_packages.py
python3 scripts/build_packages.py --check
```

Before releasing, bump the changed plugin's `version` in its portable
`plugin.json` and the root bundle version, regenerate, validate, commit, and push.
A version change allows clients with versioned caches to install the new package.
CI rejects stale generated copies, missing helpers/icons, invalid portable
manifests, invalid skills, and invalid Claude plugin/marketplace metadata.

The [portable specification](https://agent-plugins.org/plugin-authors/build-an-agent-plugin)
standardizes package contents. Marketplaces, icons, installation, and update
scheduling remain client features. Runtime availability and service login are
still device-specific.

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
