# Codex Personal Marketplace

Private Codex plugin marketplace for sharing personal plugins across devices.

## Add the marketplace

```bash
codex plugin marketplace add aldenbronkhorst/codex-personal-marketplace
```

## Install the Odoo plugin

```bash
codex plugin add odoo-project@alden-codex
```

Start a new Codex task after installing so the plugin skill is loaded.

## Publish a plugin update

Before committing plugin changes, update the `version` in
`plugins/odoo-project/.codex-plugin/plugin.json`. A new version prevents Codex
from reusing an older cached installation. Then commit and push the change.

## Update a device

```bash
codex plugin marketplace upgrade alden-codex
codex plugin add odoo-project@alden-codex
```

Start a new task after updating.
