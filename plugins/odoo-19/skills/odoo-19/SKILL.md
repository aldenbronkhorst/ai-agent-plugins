---
name: odoo-19
description: Develop, review, test, and deploy Odoo 19 modules and customizations. Use for Odoo 19 models, views, security, reports, migrations, integrations, and record changes.
---

# Odoo 19

- Target Odoo 19.
- Prefer the Odoo API for normal application work, including reading or changing records and running supported business operations. Do not default to browser automation.
- For server-side technical work such as modules, services, logs, configuration, or command-line diagnostics, use SSH when access is available.
- Use the browser only when the task specifically requires the Odoo interface or the required operation is unavailable through the API or SSH.
- Inspect the current repository and module conventions before changing code.
- Make the smallest appropriate change.
- Test the affected module and workflow on staging.
- Deploy to production only after explicit user approval.
- Before changing records, confirm the correct database and company, then verify the result.
