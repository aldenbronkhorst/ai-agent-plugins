---
name: odoo-19
description: Use, develop, review, test, and deploy Odoo 19 systems and customizations. Use for normal Odoo operations, models, views, security, reports, migrations, integrations, and record changes.
---

# Odoo 19

- Target Odoo 19.
- Prefer the Odoo API for normal application work, including reading or changing records and running supported business operations. Do not default to browser automation.
- When the user asks for a total, KPI, summary, statement, or other figure, first use an existing Odoo report, dashboard, computed field, or business method that already produces it. Preserve its filters and business context and treat the Odoo result as the source of truth; aggregate raw records only when no suitable built-in result exists or the user asks for an independent audit, reconciliation, or custom calculation.
- For Odoo 19 external API calls, default to JSON-2: send `POST /json/2/<model>/<method>` with the API key as an `Authorization: bearer ...` header and a JSON body. Add `X-Odoo-Database` only when the deployment requires an explicit database.
- For a simple access check when the URL and API key are available, make one minimal read-only JSON-2 call, such as `res.users/context_get`. Do not try `/web/session/authenticate` or legacy RPC first; use those only when the task specifically requires a login/password session or a legacy integration.
- For server-side technical work such as modules, services, logs, configuration, or command-line diagnostics, use SSH when access is available.
- Use the browser only when the task specifically requires the Odoo interface or the required operation is unavailable through the API or SSH.
- Inspect the current repository and module conventions before changing code.
- Make the smallest appropriate change.
- Test the affected module and workflow on staging.
- Deploy to production only after explicit user approval.
- Before changing records, confirm the correct database and company, then verify the result.
