---
name: odoo-project
description: Work on the Lots Lots More Odoo 19 project using its repository, branches, credentials, staging workflow, production approval gate, and company-verification safeguards. Use for development, investigation, deployment, or record changes involving this Odoo project.
---

# Odoo Project

- Odoo version: 19.
- GitHub repository: `aldenbronkhorst/lotslotsmore`.
- Staging branch: `staging2`.
- Production branch: `lotslotsmore`.
- GitHub is available through the locally authenticated `gh` and `git` tools.
- API and SSH credentials are stored in Proton Pass under `Odoo API - Staging`,
  `Odoo API - Production`, `Odoo.sh - Staging`, and `Odoo.sh - Production`.
- Use the `proton-pass` skill for credentials. Never expose or save secrets.

For development, obtain the repository from GitHub when needed, inspect Odoo 19,
make the smallest appropriate change, and test it thoroughly on staging. Report
the result and deploy to production only after the user explicitly approves it.

Before changing Odoo records, confirm the correct company and verify the result.
