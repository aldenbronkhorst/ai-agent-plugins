# AI Agent Plugins

Private collection of reusable instructions and adapters for AI coding agents.
Shared project guidance lives under `shared/`; platform-specific packaging can
be added alongside it. Codex is the first supported adapter, not the identity
of the repository.

## Layout

- `plugins/proton-pass/` provides portable Proton Pass CLI access and session
  recovery for agents. It is the first marketplace entry.
- `shared/odoo-project/AGENTS.md` contains portable project guidance.
- `plugins/odoo-project/` packages that guidance as a Codex plugin.
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

Install the Odoo project adapter when needed:

```bash
codex plugin add odoo-project@ai-agent-plugins
```

Start a new Codex task after installing so the plugin skill is loaded.

## Proton Pass on a new device

Install `pass-cli` using the [official installation instructions](https://protonpass.github.io/pass-cli/get-started/installation/)
for macOS, Linux, or Windows, then complete `pass-cli login` once. For
unattended recovery, provide a minimally scoped Personal Access Token through
`PROTON_PASS_PERSONAL_ACCESS_TOKEN` only for the wrapper process. The plugin
does not store the token.

## Publish a plugin update

Before committing plugin changes, update that plugin's `version` in its
`.codex-plugin/plugin.json`. A new version prevents Codex from reusing an older
cached installation. Then commit and push the change.

## Update a device

```bash
codex plugin marketplace upgrade ai-agent-plugins
codex plugin add proton-pass@ai-agent-plugins
codex plugin add odoo-project@ai-agent-plugins
```

Start a new task after updating.
