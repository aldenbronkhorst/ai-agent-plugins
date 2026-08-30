# AI Agent Plugins

Private collection of reusable plugins for AI coding agents. Codex is the first
supported marketplace, not the identity of the repository.

## Layout

- `plugins/proton-pass/` provides portable Proton Pass CLI access and session
  recovery for agents. It is the first marketplace entry.
- `plugins/odoo-19/` provides minimal, project-neutral Odoo 19 development and
  deployment guidance.
- `plugins/agent-core/` provides foundational guidance for secure credentials,
  direct tool use, appropriate dependency setup, target confirmation, and
  result verification.
- Future adapters for other AI agents can be added without renaming the
  repository.

## Install in Codex

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

Start a new Codex task after installing so the plugin skill is loaded.

## Proton Pass on a new device

Install `pass-cli` using the [official installation instructions](https://protonpass.github.io/pass-cli/get-started/installation/)
for macOS, Linux, or Windows. The wrapper maintains an isolated agent session,
checks it before every command, and performs one verified recovery when
authentication expires. For unattended recovery, inject a minimally scoped
Personal Access Token through `PROTON_PASS_PERSONAL_ACCESS_TOKEN`. On macOS,
the wrapper can instead read its generic Keychain entry and can migrate the
former local Codex entry. The plugin never stores the token in its files.

## Publish a plugin update

Before committing plugin changes, update that plugin's `version` in its
`.codex-plugin/plugin.json`. A new version prevents Codex from reusing an older
cached installation. Then commit and push the change.

## Update a device

```bash
codex plugin marketplace upgrade ai-agent-plugins
codex plugin add proton-pass@ai-agent-plugins
codex plugin add odoo-19@ai-agent-plugins
codex plugin add agent-core@ai-agent-plugins
```

Start a new task after updating.
