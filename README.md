# AI Agent Plugins

Private collection of reusable instructions and adapters for AI coding agents.
Shared project guidance lives under `shared/`; platform-specific packaging can
be added alongside it. Codex is the first supported adapter, not the identity
of the repository.

## Layout

- `shared/odoo-project/AGENTS.md` contains portable project guidance.
- `plugins/odoo-project/` packages that guidance as a Codex plugin.
- Future adapters for other AI agents can be added without renaming the
  repository.

## Install in Codex

Add the GitHub-backed marketplace:

```bash
codex plugin marketplace add aldenbronkhorst/ai-agent-plugins
```

Install the Odoo project adapter:

```bash
codex plugin add odoo-project@alden-agents
```

Start a new Codex task after installing so the plugin skill is loaded.

## Publish a plugin update

Before committing plugin changes, update the `version` in
`plugins/odoo-project/.codex-plugin/plugin.json`. A new version prevents Codex
from reusing an older cached installation. Then commit and push the change.

## Update a device

```bash
codex plugin marketplace upgrade alden-agents
codex plugin add odoo-project@alden-agents
```

Start a new task after updating.
