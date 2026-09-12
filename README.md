# AI Agent Plugins

Eight plugins for **Hermes Agent, Claude Code and Codex**, sharing the same Agent
Skills, helper scripts and icons. Each platform gets its native packaging; the
workflow instructions and service integrations have one maintained source.

## Install in Hermes

Install the plugins you want individually. In **Capabilities → Plugins → Install
from Git**, paste a plugin link from the table below. For example, Proton Pass:

```text
https://github.com/aldenbronkhorst/ai-agent-plugins/tree/main/plugins/proton-pass
```

Install and enable **proton-pass**, then restart Hermes Desktop and start a new
session. For the CLI, exit and start Hermes again. The installer labels the component type **Agent plugin**;
the plugin identity underneath is `proton-pass`.

The equivalent CLI command is:

```bash
hermes plugins install aldenbronkhorst/ai-agent-plugins/plugins/proton-pass --enable
```

Ask for the work normally, for example **"Explain how you would use Proton Pass
to supply credentials without displaying them"** or **"How should I connect to
Odoo 19?"**. Enabled plugins advertise their workflow descriptions in the agent's
session context. The agent loads the corresponding instructions with Hermes'
native `skill_view` tool, including access to their bundled scripts/resources.
No manual global skill copies or custom instructions are needed.

### Select a plugin manually in Hermes

Hermes does not automatically turn plugin-provided skills into `/name` commands.
To add a manual shortcut, use its native
[skill bundles](https://hermes-agent.nousresearch.com/docs/user-guide/features/skills#skill-bundles) once after installing
the plugin. For example:

```bash
hermes bundles create proton-pass --skill proton-pass:proton-pass --description "Use the Proton Pass plugin"
hermes bundles create odoo-19 --skill odoo-19:odoo-19 --description "Use the Odoo 19 plugin"
hermes bundles create agent-core --skill agent-core:agent-core --description "Use the Agent Core plugin"
```

Create shortcuts only for plugins you have installed. After the restart, start a new session and
type `/proton-pass`, `/odoo-19`, or `/agent-core` at the beginning of the composer, followed by
your request. Hermes offers them in slash-command completions and loads the
referenced skill into the conversation when invoked. The same pattern applies
to the other plugins: `hermes bundles create NAME --skill NAME:NAME`.

For example: `/odoo-19 Check Production access using Proton Pass`. A slash name
typed inside an ordinary sentence is not the same as invoking the command at
the start. Natural requests still work when the plugin context has loaded.

These shortcuts contain skill names, not copies of the instructions or helpers.
They continue to reference the installed package after updates. Disabling or
uninstalling a plugin prevents its shortcut from loading the skill; the shortcut
itself remains in Hermes until removed with `hermes bundles delete NAME`.
Existing shortcuts are not overwritten unless you explicitly pass `--force`.
This is a separate, one-time Hermes setup step; the Git plugin installer does
not create these shortcuts automatically. If you installed the optional root
bundle instead, use `--skill ai-agent-plugins:NAME`.

### Update in Hermes

To update an individual plugin, paste the same link into **Install from Git**,
turn on **Force reinstall**, and keep it enabled. The equivalent native command:

```bash
hermes plugins install aldenbronkhorst/ai-agent-plugins/plugins/proton-pass --force --enable
```

Hermes' current subdirectory installer records the source/revision but does not
retain `.git`, so its **Update** action cannot pull these installations. Native
force-reinstall fetches the current package and replaces it, including removing
stale files. Restart Hermes Desktop after updating, then start a new session. **Individual Hermes folder
installs do not currently provide automatic background updates.**

### Diagnose a missing workflow

An enabled row in **Capabilities → Plugins** confirms the on-disk installation;
it does not prove a running agent loaded it. Hermes caches plugin discovery in
the backend process. **Rescan** refreshes the catalog, and opening a new chat can
reuse that process with its old registrations. Restart the app after installing,
enabling, or updating plugins, then use a fresh chat. Existing conversations can
retain their earlier system prompt even after restarting.

In that fresh chat, ask Hermes to list plugin skills with `skills_list`. Installed
individual packages should appear as `odoo-19:odoo-19`,
`proton-pass:proton-pass`, and `agent-core:agent-core` (for whichever you installed).
Old `agent-plugin-...` names belong to the earlier portable packaging and must
not be reused for the current native packages.

For a read-only Odoo check, identify the environment in the request, for example
"Check Production Odoo access using Proton Pass." If both Production and Staging
credential items exist and no target was given, the credential runner reports
the ambiguity and waits for a target. That is expected selection behavior, not
an authentication failure. A successful check returns `res.users/context_get`;
no Odoo records need to be changed.

The repository root remains an optional **single bundle** named `ai-agent-plugins`
for existing users. It contains all eight workflows, has one enable switch, and
retains Git for `hermes plugins update ai-agent-plugins`. It is not the eight-entry
marketplace. Choose either the bundle or individual plugins to avoid duplicates.

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

Each plugin name links to the exact directory to paste into Hermes' Git installer.
Codex and Claude expose the same names through their native marketplace catalogs.

| Plugin / Hermes install link | Purpose |
| --- | --- |
| [proton-pass](https://github.com/aldenbronkhorst/ai-agent-plugins/tree/main/plugins/proton-pass) | Credential retrieval and session recovery using Proton Pass. |
| [odoo-19](https://github.com/aldenbronkhorst/ai-agent-plugins/tree/main/plugins/odoo-19) | Odoo 19 development, deployment, and operations. |
| [agent-core](https://github.com/aldenbronkhorst/ai-agent-plugins/tree/main/plugins/agent-core) | Credential handling, tool selection, and result verification. |
| [microsoft-graph](https://github.com/aldenbronkhorst/ai-agent-plugins/tree/main/plugins/microsoft-graph) | Microsoft 365 and Entra through Microsoft Graph. |
| [github-cli](https://github.com/aldenbronkhorst/ai-agent-plugins/tree/main/plugins/github-cli) | GitHub through the official CLI and Git. |
| [azure-cli](https://github.com/aldenbronkhorst/ai-agent-plugins/tree/main/plugins/azure-cli) | Azure subscriptions and resources through the official CLI. |
| [exchange-online](https://github.com/aldenbronkhorst/ai-agent-plugins/tree/main/plugins/exchange-online) | Exchange administration through official PowerShell tools. |
| [sharepoint-online](https://github.com/aldenbronkhorst/ai-agent-plugins/tree/main/plugins/sharepoint-online) | SharePoint through Graph and the official management shell. |

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

The build generates `.codex-plugin/plugin.json`, `.claude-plugin/plugin.json`,
the Claude marketplace catalog, and Hermes' `plugin.yaml`, `hermes-skills.json`
and `__init__.py`. The original `.agents/plugins/marketplace.json` retains the
Codex catalog order, availability policies and display name.

Hermes registration comes from one template, `packaging/hermes/__init__.py`.
It registers the canonical skill files and bounded discovery context, including
their installed directory for resolving helper paths, using native Hermes APIs.
That context survives prompt rebuilds; disabling/removing a plugin
removes its registrations on reload. The adapter does not execute helpers,
install service runtimes, retrieve credentials, or copy skills into global folders.
Its runtime uses Python's standard library only.

After editing canonical content:

```bash
python3 -m venv .venv
.venv/bin/python -m pip install PyYAML==6.0.3 jsonschema==4.23.0 skills-ref==0.1.1
.venv/bin/python scripts/build_packages.py
.venv/bin/python scripts/validate_packages.py
.venv/bin/python -m unittest discover -s tests -v
```

Before releasing, bump the changed plugin's `version` in its portable
`plugin.json` and the root bundle version, regenerate, validate, commit, and push.
A version change allows clients with versioned caches to install the new package.
CI rejects stale generated copies, missing helpers/icons, invalid portable
manifests, invalid skills, mismatched versions, broken registration and invalid
Claude plugin/marketplace metadata.

Run the Hermes integration test with an installed Hermes runtime and its Python:

```bash
/path/to/hermes-agent/venv/bin/python scripts/test_hermes_integration.py \
  --hermes-source /path/to/hermes-agent
```

This uses a temporary Git repository and isolated Hermes profile. It exercises
native installation of all eight plugins, `skill_view`, real agent prompt
construction/rebuild, native manual shortcuts through Desktop's completion and
dispatch backend, disable/re-enable, replacement updates and unload. It makes
no model API calls and does not access service accounts. A live model invocation
is a separate release check; manifest validation alone is not runtime validation.

The packaging follows the shared-content/native-registration pattern used by
[Superpowers](https://github.com/obra/superpowers/tree/main/.hermes-plugin) and
the generated platform manifests in [Xberg](https://github.com/xberg-io/plugins).

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
